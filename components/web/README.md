# Web

## Purpose

A practical framework-neutral Web/TypeScript profile with reviewed HTML, CSS, SCSS, Less, JavaScript, TypeScript, JSX/TSX, Emmet, Tailwind, and ESLint support.

## Belongs here

Browser-development language behavior, frontend file support, Web formatter/linter integrations, and broadly useful frontend extensions.

## Does not belong here

Database tools, database connections, Python/Flask behavior, PHP language tooling, containers, deployment credentials, or repository-specific Node versions.

## Standalone profile recipe

```yaml
name: Web
components:
  - main
  - web
```

## Reused by

Web and future Flask, React, Angular/Nx, Web Testing, React Native, and Web + Database profiles.

Database-enabled Web work composes `database` and, when needed, a vendor component. The Web component remains independently usable.

## Portability classification

Current settings are portable and contain no project paths, package-manager state, database state, or account data.

## Platform concerns

Node and browser executable locations remain platform or machine concerns.

## Machine concerns

Node installation paths, global package locations, certificates, browser paths, and database connection details remain private.

## Workspace concerns

Repositories should decide whether ESLint is enabled, which formatter owns each language, whether Tailwind, Nx, Playwright, Vitest, or React Native applies, and which database stack is required.

## Performance concerns

ESLint and Tailwind are included for the MVP but should be disabled or removed in workspaces that do not use them. Database language servers and connection explorers are not loaded by the base Web profile.

## Deferred decisions

Split Tailwind, Angular/Nx, React Native, Playwright/Vitest, and framework-specific settings into smaller components after the Web profile is validated.
