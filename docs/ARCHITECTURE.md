# Architecture

## Components and profiles

A component is a focused reusable unit with portable `settings.jsonc`, an extension list, and ownership documentation. Every component can participate in a standalone profile when combined with `suggested-baseline`.

A profile is an explicit YAML recipe. Profiles do not inherit other profiles and no parser is implemented.

## Layers

```text
Portable component settings
→ explicit profile recipe
→ platform settings
→ machine-local settings
→ workspace settings
```

The order is conceptual. Manual VS Code profiles and Settings Sync remain the runtime mechanism.

## Suggested Baseline

The baseline is a lightweight daily driver for common repository formats and navigation. It intentionally excludes heavy language ecosystems, databases, container management, SDK managers, deep indexers, and unresolved measurement candidates.

## Focused components

- `default` adds optional cross-stack daily tools.
- `cpp` owns general C/C++.
- `unreal` owns only Unreal-specific concerns and reuses `cpp`.
- `powershell`, `web`, and `python` own their language/workflow behavior.

## Platform overlays

Committed Windows and Linux files contain reusable OS preferences. Windows prefers PowerShell 7; Linux defaults to Bash and keeps PowerShell optional.

## Machine-local overlays

Ignored local files contain absolute executable paths, SDK roots, compiler paths, credentials, and device tuning.

## Workspace settings

Repositories own generated-folder exclusions, include paths, compile commands, team formatter policy, and project-specific extension behavior.

## Future composition

A future tool may merge components, validate conflicts, materialize profiles, and create exports. It must not be built until the manual profiles are stable.
