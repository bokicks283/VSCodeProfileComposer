# Database

## Purpose

Provides an opt-in, vendor-neutral foundation for SQL editing and generic database work without adding database tooling to Main, Web, or Python.

## Belongs here

Generic SQL editing, vendor-neutral query tooling, shared database documentation, portable SQL behavior, and generic extension recommendations that do not assume SQL Server, PostgreSQL, MySQL/MariaDB, SQLite, or MongoDB.

## Does not belong here

Vendor-specific language servers, drivers, connection settings, saved connections, hosts, usernames, passwords, tokens, certificates, account IDs, cloud resources, private database names, or employer-specific tooling.

## Standalone profile recipe

```yaml
name: Database
components:
  - main
  - database
```

## Reused by

Database, Web + Database, Python + Database, future Flask/PHP composites, and vendor-specific profiles.

## Portability classification

The component contains only the generic SQLTools extension. No connection object or machine-specific path is committed.

## Vendor separation

- SQL Server behavior belongs in `sql-server`.
- MongoDB behavior belongs in `mongodb`.
- PostgreSQL, MySQL/MariaDB, and SQLite remain planned components until reviewed configuration justifies creating them.

## Platform concerns

Database command-line clients, native drivers, certificates, and credential stores differ by platform and remain outside this component.

## Machine concerns

Connection profiles, authentication caches, local client paths, SSH tunnels, certificates, and employer-managed resources stay local or employer-managed.

## Workspace concerns

Repositories own schema projects, migrations, query conventions, environment selection, and team connection policy.

## Performance concerns

Database extensions can add background services, language servers, connection explorers, and extra UI. This component is therefore opt-in even when its tooling is vendor-neutral.

## Deferred decisions

Whether SQLTools remains the preferred generic client, which formatter should own `[sql]`, and whether PostgreSQL, MySQL/MariaDB, or SQLite components should be created.
