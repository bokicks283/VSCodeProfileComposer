# MongoDB

## Purpose

Adds reviewed MongoDB-specific language support and explorer tooling on top of the generic Database component.

## Belongs here

`mongodbLanguageServer.*` settings, the MongoDB VS Code extension, MongoDB language behavior, and MongoDB-specific explorer workflow.

## Does not belong here

Generic SQL tooling, SQL Server settings, connection strings, saved connections, hosts, database names, usernames, passwords, tokens, certificates, account IDs, authentication caches, or employer-specific cloud resources.

## Standalone profile recipe

```yaml
name: MongoDB
components:
  - main
  - database
  - mongodb
```

## Reused by

MongoDB and future Web, Python, Node, Flask, or employer-specific profiles that explicitly need MongoDB.

## Portability classification

The active setting limits reported language-server problems and contains no connection or account data.

## Platform concerns

Shell executables, certificates, SSH tunnels, and local MongoDB tools remain platform or machine concerns.

## Machine concerns

Saved connections, authentication state, Atlas accounts, private clusters, hosts, ports, database names, and certificates remain outside the repository.

## Workspace concerns

Repositories own schema conventions, migrations, seed data, environment selection, and team connection policy.

## Performance concerns

The MongoDB extension can add a language server and explorer UI, so it is loaded only through explicit MongoDB composition.

## Deferred decisions

The previous `mdb.mcp.server` preference is not migrated because its ownership and desired cross-machine behavior are not yet clear. Revisit MCP integration only when a concrete MongoDB workflow requires it.
