#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIP="192.168.60.20"
PGBOUNCER_PORT="6432"

declare -A PG_IP=(
  [pg01]="192.168.60.11"
  [pg02]="192.168.60.12"
  [pg03]="192.168.60.13"
)

OLD_PRIMARY=""
VIP_OWNER=""

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

cleanup() {
  cd "$ROOT"

  if [[ -n "${OLD_PRIMARY}" ]]; then
    vagrant ssh "$OLD_PRIMARY" \
      -c "sudo systemctl start patroni" \
      >/dev/null 2>&1 || true
  fi

  if [[ -n "${VIP_OWNER}" ]]; then
    vagrant ssh "$VIP_OWNER" \
      -c "sudo systemctl start keepalived" \
      >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

find_primary() {
  local node

  for node in pg01 pg02 pg03; do
    if curl -fsS \
      --max-time 2 \
      "http://${PG_IP[$node]}:8008/primary" \
      >/dev/null 2>&1; then

      echo "$node"
      return 0
    fi
  done

  return 1
}

has_vip() {
  local node="$1"

  vagrant ssh "$node" \
    -c "ip -4 addr show dev eth1 | grep -q '${VIP}/'" \
    >/dev/null 2>&1
}

database_write() {
  local marker="$1"
  local password

  password="$(
    sed -n \
      's/^patroni_superuser_password: "\(.*\)"/\1/p' \
      "$ROOT/ansible/inventory/secrets/postgres.yml"
  )"

  for _ in $(seq 1 30); do
    if vagrant ssh ops01 -c "
      PGPASSWORD='$password' \
      /usr/lib/postgresql/18/bin/psql \
        -h $VIP \
        -p $PGBOUNCER_PORT \
        -U postgres \
        -d appdb \
        -v ON_ERROR_STOP=1 \
        -Atc \"
          CREATE TABLE IF NOT EXISTS app.ha_validation (
              id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
              marker text NOT NULL,
              created_at timestamptz NOT NULL DEFAULT now()
          );

          INSERT INTO app.ha_validation(marker)
          VALUES ('$marker')
          RETURNING id, marker;
        \"
    "; then
      return 0
    fi

    sleep 1
  done

  return 1
}

cd "$ROOT"

echo "=== INITIAL PRIMARY ==="

OLD_PRIMARY="$(find_primary)" ||
  fail "unable to detect PostgreSQL primary"

echo "$OLD_PRIMARY (${PG_IP[$OLD_PRIMARY]})"

echo
echo "=== STOPPING PRIMARY PATRONI ==="

vagrant ssh "$OLD_PRIMARY" \
  -c "sudo systemctl stop patroni"

NEW_PRIMARY=""

for _ in $(seq 1 60); do
  candidate="$(find_primary || true)"

  if [[ -n "$candidate" && "$candidate" != "$OLD_PRIMARY" ]]; then
    NEW_PRIMARY="$candidate"
    break
  fi

  sleep 1
done

[[ -n "$NEW_PRIMARY" ]] ||
  fail "new PostgreSQL primary was not elected"

echo
echo "=== NEW PRIMARY ==="
echo "$NEW_PRIMARY (${PG_IP[$NEW_PRIMARY]})"

echo
echo "=== WRITE THROUGH VIP AFTER DB FAILOVER ==="

database_write \
  "database-failover-$(date -u +%Y%m%dT%H%M%SZ)" ||
  fail "write through VIP failed after database failover"

echo
echo "=== STARTING OLD PRIMARY ==="

vagrant ssh "$OLD_PRIMARY" \
  -c "sudo systemctl start patroni"

REJOINED=false

for _ in $(seq 1 90); do
  if curl -fsS \
    --max-time 2 \
    "http://${PG_IP[$OLD_PRIMARY]}:8008/replica" \
    >/dev/null 2>&1; then

    REJOINED=true
    break
  fi

  sleep 1
done

[[ "$REJOINED" == true ]] ||
  fail "$OLD_PRIMARY did not rejoin as replica"

echo "$OLD_PRIMARY successfully rejoined as replica"

echo
echo "=== PATRONI CLUSTER ==="

vagrant ssh "$NEW_PRIMARY" -c "
  sudo /opt/patroni/bin/patronictl \
    -c /etc/patroni/patroni.yml \
    list
"

echo
echo "=== CURRENT VIP OWNER ==="

for node in proxy01 proxy02; do
  if has_vip "$node"; then
    VIP_OWNER="$node"
    break
  fi
done

[[ -n "$VIP_OWNER" ]] ||
  fail "unable to detect VIP owner"

if [[ "$VIP_OWNER" == "proxy01" ]]; then
  VIP_PEER="proxy02"
else
  VIP_PEER="proxy01"
fi

echo "$VIP_OWNER"

echo
echo "=== STOPPING KEEPALIVED ON $VIP_OWNER ==="

vagrant ssh "$VIP_OWNER" \
  -c "sudo systemctl stop keepalived"

VIP_MOVED=false

for _ in $(seq 1 30); do
  if has_vip "$VIP_PEER"; then
    VIP_MOVED=true
    break
  fi

  sleep 1
done

[[ "$VIP_MOVED" == true ]] ||
  fail "VIP did not move to $VIP_PEER"

echo "VIP moved to $VIP_PEER"

echo
echo "=== WRITE THROUGH VIP AFTER PROXY FAILOVER ==="

database_write \
  "proxy-failover-$(date -u +%Y%m%dT%H%M%SZ)" ||
  fail "write through VIP failed after proxy failover"

echo
echo "=== RESTORING KEEPALIVED ==="

vagrant ssh "$VIP_OWNER" \
  -c "sudo systemctl start keepalived"

sleep 5

echo
echo "=== VALIDATION ROWS ==="

password="$(
  sed -n \
    's/^patroni_superuser_password: "\(.*\)"/\1/p' \
    "$ROOT/ansible/inventory/secrets/postgres.yml"
)"

vagrant ssh ops01 -c "
  PGPASSWORD='$password' \
  /usr/lib/postgresql/18/bin/psql \
    -h $VIP \
    -p $PGBOUNCER_PORT \
    -U postgres \
    -d appdb \
    -Atc \"
      SELECT id, marker
      FROM app.ha_validation
      ORDER BY id DESC
      LIMIT 5;
    \"
"

echo
echo "HA VALIDATION PASSED"
