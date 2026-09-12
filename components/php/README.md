# PHP

## Purpose

Provides portable PHP language intelligence, formatting availability, and
Xdebug client support for PHP applications.

## Belongs here

PHP language intelligence, PHP-only editor behavior, and the debugger client
used with Xdebug.

## Does not belong here

PHP executable paths, PHP versions, `php.ini` locations, Xdebug ports and path
mappings, Composer configuration, framework policy, web-server configuration,
database clients, credentials, or deployment targets.

## Standalone profile recipe

```yaml
name: PHP
components:
  - main
  - php
```

## Reused by

The LAMP + LEMP profile and future PHP, Laravel, Symfony, WordPress, or PHP API
profiles.

## Portability classification

The extension IDs and editor settings are portable. Intelephense owns PHP
diagnostics and is selected as the available formatter, but automatic
formatting remains disabled unless a workspace opts in.

## Platform concerns

PHP, Composer, Xdebug, and their packages are installed and configured by the
operating system. The component does not choose a PHP version or package
source.

## Machine concerns

Absolute PHP executable paths, Xdebug IDE keys, certificates, and local runtime
locations stay machine-local.

## Workspace concerns

Repositories own PHP and Composer version constraints, framework tooling,
format-on-save policy, static analysis, tests, debugger launch configurations,
Xdebug path mappings, and environment variables.

## Performance concerns

Intelephense starts for PHP files and indexes the open workspace. Xdebug client
support activates for PHP debug sessions and commands. Large dependency or
generated trees should be excluded by the repository when measurements justify
it.

## Deferred decisions

PHPStan, Psalm, PHPUnit integration, framework helpers, Composer tooling, and
opinionated coding-standard formatters remain workspace- or future
component-specific choices.
