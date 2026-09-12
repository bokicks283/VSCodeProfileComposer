# MySQL and MariaDB

## Purpose

Adds MySQL and MariaDB connectivity to the generic SQLTools foundation.

## Belongs here

The SQLTools MySQL/MariaDB driver and future portable behavior that applies to
both database engines.

## Does not belong here

The generic SQLTools client, saved connections, hosts, ports, database names,
usernames, passwords, TLS certificates, SSH tunnels, command-line client paths,
or schema and migration policy.

## Standalone profile recipe

```yaml
name: MySQL + MariaDB
components:
  - main
  - database
  - mysql-mariadb
```

## Reused by

The LAMP + LEMP profile and future MySQL- or MariaDB-backed application
profiles.

## Portability classification

The driver extension ID is portable. All connection and authentication state
remains outside the repository.

## Platform concerns

Database servers, command-line clients, native libraries, service management,
and certificate stores differ by distribution and operating system.

## Machine concerns

Connections, credentials, SSH tunnels, local socket paths, client executable
paths, and authentication caches stay local.

## Workspace concerns

Repositories own schemas, migrations, seed data, database engine/version
requirements, and team connection policy.

## Performance concerns

The driver participates in SQLTools activation and connection exploration, so
it is included only in recipes that explicitly need MySQL or MariaDB.

## Deferred decisions

No default engine, port, socket, SSL mode, or connection is selected.
