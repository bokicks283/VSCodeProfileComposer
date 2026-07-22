# SQL Server

## Purpose

Adds reviewed SQL Server-specific editing and object-explorer behavior on top of the generic Database component.

## Belongs here

`mssql.*` behavior settings, the official SQL Server extension, T-SQL behavior, SQL Server object exploration, SQL Server-specific query tooling, and SQL Server-only keybindings.

## Does not belong here

Generic SQL ownership, MongoDB behavior, live connections, connection groups, servers, databases, usernames, passwords, tokens, certificates, account IDs, or employer-specific Azure resources.

## Standalone profile recipe

```yaml
name: SQL Server
components:
  - default
  - database
  - sql-server
```

## Reused by

SQL Server and future enterprise, C#, Python, Web, migration, or administration profiles that explicitly need SQL Server.

## Portability classification

The five active `mssql.*` settings and the IntelliSense-cache rebuild keybinding are reviewed behavior preferences. No saved connection or authentication object is committed.

## Platform concerns

Native drivers, Azure authentication, local SQL Server instances, command-line tools, and certificate behavior remain platform or machine concerns.

## Machine concerns

All connection profiles, groups, hosts, ports, databases, usernames, passwords, tokens, certificates, and cached authentication state remain outside the repository.

## Workspace concerns

Azure Functions SQL bindings, `.sqlproj` schema projects, migrations, deployment targets, and team connection policy are project-specific.

## Performance concerns

The official SQL Server extension may add language services and object-explorer UI, so it is loaded only through explicit SQL Server composition.

## Deferred decisions

`ms-mssql.sql-bindings-vscode` remains project-only for Azure Functions SQL bindings. `ms-mssql.sql-database-projects-vscode` remains project-only for `.sqlproj` work. The SQLTools MSSQL driver remains deferred to avoid overlapping SQL Server clients without a validated need.
