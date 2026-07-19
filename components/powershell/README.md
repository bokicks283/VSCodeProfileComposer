# PowerShell

## Purpose

Provides PowerShell language support and the reviewed Command Explorer preference.

## Belongs here

PowerShell extension behavior, language settings, debugging, testing, and formatting decisions.

## Does not belong here

The operating system's default terminal selection, absolute `pwsh` paths, credentials, execution-policy changes, or machine module paths.

## Standalone profile recipe

```yaml
name: PowerShell
components:
  - suggested-baseline
  - powershell
```

## Reused by

The PowerShell profile and future automation or Windows-administration profiles.

## Portability classification

The current component is portable.

## Platform concerns

Windows prefers PowerShell 7 in `platform/windows.jsonc`. Linux keeps Bash as default and exposes PowerShell only as an optional profile.

## Machine concerns

Module paths, remoting endpoints, certificates, and local executable paths remain private.

## Workspace concerns

Repository-specific PSScriptAnalyzer rules, module paths, test tasks, and execution commands belong in the project.

## Performance concerns

Use one PowerShell extension instance and avoid duplicate PowerShell language tooling.

## Deferred decisions

PSScriptAnalyzer formatting ownership and project-specific test integration.
