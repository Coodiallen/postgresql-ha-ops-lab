# PostgreSQL HA Ops Lab

A hands-on PostgreSQL/DevOps lab I built to practice running a small highly available database platform rather than just installing PostgreSQL on a single VM.

The whole environment runs on Vagrant + libvirt and is configured with Ansible.

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
└── pgBackRest repository

restore01
├── isolated PITR restore
└── logical replication subscriber
```

The PostgreSQL cluster consists of three Patroni nodes with etcd used as the distributed configuration store. Two proxy nodes provide a floating VIP, connection pooling and routing to the current primary.

## What is included

- PostgreSQL 18 HA cluster with Patroni and etcd
- HAProxy + Keepalived VIP
- PgBouncer transaction pooling
- Ansible-based configuration
- application schema, RBAC and audit triggers
- Prometheus, Grafana and PostgreSQL metrics
- encrypted pgBackRest backups and WAL archiving
- point-in-time recovery on an isolated restore host
- logical replication
- pg_cron jobs
- pgbench testing and query/index tuning
- automated HA failover validation
- GitHub Actions syntax validation

## What I tested

This lab was not only deployed — I intentionally broke parts of it to check how they recover.

PostgreSQL primary failover was tested by stopping Patroni on the leader. A new primary was elected, writes continued through the same VIP, and the old primary successfully rejoined as a replica.

Keepalived failover was also tested by stopping the active proxy. The VIP moved from `proxy01` to `proxy02`, database writes continued, and the VIP returned after the original node came back.

pgBackRest was tested with a real PITR scenario: data was deleted from the live database and restored on `restore01` to a named restore point from before the deletion.

For one test query, adding the proper index changed the plan from a sequential scan over ~150k rows to an index scan and reduced execution time from about **8.5 ms to 0.09 ms**.

## Lab nodes

```text
pg01       192.168.60.11
pg02       192.168.60.12
pg03       192.168.60.13

VIP        192.168.60.20
proxy01    192.168.60.21
proxy02    192.168.60.22

ops01      192.168.60.30
restore01  192.168.60.40
```

## Running the lab

Start the VMs:

```bash
vagrant up
```

Ansible configuration is split into small playbooks under `ansible/playbooks/`.

The general deployment order is:

```text
common
  → etcd
  → patroni
  → haproxy
  → keepalived
  → pgbouncer
  → database
  → monitoring
  → backup / restore
  → advanced database features
```

Passwords and other local secrets are stored in:

```text
ansible/inventory/secrets/postgres.yml
```

This directory is ignored by Git.

The HA validation script can be run with:

```bash
./scripts/ha-failover-test.sh
```

## Why I built it

The main goal was to get practical experience with PostgreSQL operations around the database itself: HA, failover, connection routing, backups, recovery, monitoring, replication and basic performance troubleshooting.

It is a lab, not a production-ready PostgreSQL platform, but most of the scenarios here were implemented and tested rather than only described in configuration files.