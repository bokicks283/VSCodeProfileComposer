# Apache and NGINX

## Purpose

Provides syntax support for the two web-server families used by LAMP and LEMP
development.

## Belongs here

Portable Apache and NGINX configuration-language extensions and behavior that
is useful wherever those server configurations are edited.

## Does not belong here

Server installation, service control, enabled-site layout, document roots,
virtual hosts, TLS keys and certificates, reverse-proxy destinations, PHP-FPM
socket paths, deployment credentials, or production policy.

## Standalone profile recipe

```yaml
name: Apache + NGINX
components:
  - main
  - apache-nginx
```

## Reused by

The LAMP + LEMP profile and future web-server administration profiles.

## Portability classification

The extensions are portable. Their broad `.conf` language contributions
overlap, so consuming profiles should add explicit `files.associations` for
well-known Apache and NGINX filenames and directory layouts.

## Platform concerns

Configuration directories, service names, module layout, and validation
commands vary across Linux distribution families.

## Machine concerns

Local server roots, executable paths, privileged-edit workflows, certificates,
and deployment endpoints stay machine-local.

## Workspace concerns

Repositories own virtual hosts, reverse proxies, document roots, TLS policy,
PHP-FPM integration, container topology, and deployment automation.

## Performance concerns

The Apache extension contributes syntax only. The NGINX extension activates
for NGINX and embedded Lua files. Neither server is started or queried by the
profile.

## Deferred decisions

Server linting, formatting, privileged remote editing, container tooling, and
deployment integrations remain environment-specific.
