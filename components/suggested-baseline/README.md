# Suggested Baseline

## Purpose

A lightweight daily driver for repository navigation, Git/GitHub work, Markdown, JSON/JSONC, YAML, XML, TOML, dotenv, properties-style INI/CFG files, CSV text, PowerShell file recognition, and basic source browsing.

## Belongs here

Portable editor behavior and broadly useful, low-overhead format or repository extensions.

## Does not belong here

Heavy language servers, database clients, container tooling, SDK managers, framework scanners, compiler paths, credentials, or project exclusions.

## Standalone profile recipe

```yaml
name: Suggested Baseline
components:
  - suggested-baseline
```

## Reused by

Every profile in `profiles/`.

## Portability classification

All active settings are portable. `todo-tree.ripgrep.ripgrep` uses the executable name `rg`; a machine may override it with an absolute path.

## Platform concerns

Terminal defaults are owned by `platform/`, not this component.

## Machine concerns

The current Windows machine requires a machine-local absolute Todo Tree ripgrep path. The real personal path is intentionally excluded from this public repository.

## Workspace concerns

Generated folders and repository-specific excludes belong in workspace settings.

## Performance concerns

Project Manager, CODEOWNERS, All Autocomplete, Shift That, and Path Intellisense were not placed in this baseline because they still require repair or isolated measurement.

## Deferred decisions

Whether INI-specific validation is safe for Unreal syntax and whether additional globally useful navigation extensions earn baseline status.
