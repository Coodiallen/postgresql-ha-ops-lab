# PostgreSQL HA Ops Lab

A small PostgreSQL HA lab built with Vagrant, libvirt and Ansible.

The idea was to build and test a PostgreSQL setup with failover, connection pooling, monitoring, backups and recovery across several VMs.

## Architecture

```text
                         192.168.60.20
Client  ──>  Keepalived VIP :6432
                    │
               PgBouncer
                    │
               HAProxy :5000
                    │
         ┌──────────┼──────────┐
         │          │          │
       pg01       pg02       pg03
         └── PostgreSQL 18 ───┘
               Patroni
                 etcd

ops01
├── Prometheus
├── Grafana
└── pgBackRest

restore01
├── PITR restore
└── logical replication subscriber
```

The PostgreSQL cluster runs on three Patroni nodes with etcd. Two proxy nodes provide a floating VIP, PgBouncer connection pooling and HAProxy routing to the current primary.

## What's in the lab

- PostgreSQL 18 + Patroni + etcd
- HAProxy, Keepalived and PgBouncer
- Prometheus and Grafana monitoring
- pgBackRest backups and WAL archiving
- point-in-time recovery
- logical replication
- pg_cron
- RBAC and audit triggers
- pgbench and basic query tuning
- Ansible automation
- GitHub Actions validation

## Tested scenarios

I tested PostgreSQL failover by stopping Patroni on the primary. Another node became primary, writes continued through the same VIP, and the old primary later rejoined as a replica.

I also tested proxy failover by stopping Keepalived on the active proxy. The VIP moved to the second proxy and database access continued normally.

For recovery testing, I deleted data from the live database and restored it on `restore01` to a restore point created before the deletion.

As a small performance test, an index changed one query from a sequential scan over about 150k rows to an index scan, reducing execution time from roughly **8.5 ms to 0.09 ms**.

## Running it

Start the VMs:

```bash
vagrant up
```

Ansible playbooks are in:

```text
ansible/playbooks/
```

Local passwords and other secrets are stored in:

```text
ansible/inventory/secrets/postgres.yml
```

and are excluded from Git.

HA failover can be tested with:

```bash
./scripts/ha-failover-test.sh
```
