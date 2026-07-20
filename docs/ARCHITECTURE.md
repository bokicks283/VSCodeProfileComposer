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

The baseline is the lightweight daily driver for common repository formats, source browsing, general terminal behavior, and routine shell-language work across mixed repositories and machines.

It owns:

- basic PowerShell support through the Microsoft PowerShell extension
- PowerShell, Bash/Zsh shell-script, and Windows batch file associations
- terminal behavior that is portable and not operating-system-specific
- common navigation and formatting commands

Default therefore supports everyday `.ps1`, `.psm1`, `.psd1`, `.sh`, `.bash`, `.zsh`, `.bat`, and `.cmd` work without composing the PowerShell component.

The Microsoft PowerShell placement is provisional: available evidence shows PowerShell language/debug/command activation and prior cross-profile ownership, but no reliable activation-time measurement. Revisit it if later Default measurements show a meaningful cost.

## Focused components

- `default` adds optional cross-stack daily tools.
- `cpp` owns general C/C++.
- `unreal` owns only Unreal-specific concerns and reuses `cpp`.
- `web` and `python` own their language/workflow behavior.
- `powershell` owns only advanced PowerShell development concerns such as Command Explorer, module authoring, dedicated testing/analysis, advanced debugging, and administration tooling.

## Platform overlays

Committed Windows and Linux files contain reusable OS preferences. Windows prefers PowerShell 7; Linux defaults to Bash and keeps PowerShell optional. Platform defaults are not duplicated in components.

## Machine-local overlays

Ignored local files contain absolute executable paths, SDK roots, compiler paths, credentials, module paths, remoting endpoints, and device tuning.

## Workspace settings

Repositories own generated-folder exclusions, include paths, compile commands, team formatter policy, PSScriptAnalyzer/Pester rules, module paths, and project-specific extension behavior.

## Future composition

A future tool may merge components, validate conflicts, materialize profiles, and create exports. It must not be built until the core manual profiles are stable.
