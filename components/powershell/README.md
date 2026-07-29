# PowerShell Development

## Purpose

Adds advanced PowerShell development behavior on top of the everyday PowerShell support already present in Main.

The current reviewed overlay enables Command Explorer for dedicated module, administration, debugging, testing, and analysis work.

## Belongs here

Advanced PowerShell extension settings, module-authoring workflow, Command Explorer, dedicated Pester/PSScriptAnalyzer behavior, advanced debugging, Azure or Microsoft administration tooling, publishing workflows, and settings that add background work or UI clutter unnecessary for ordinary scripts.

## Does not belong here

Basic `.ps1`, `.psm1`, or `.psd1` editing; the Microsoft PowerShell extension itself; general terminal behavior; the operating system's default terminal selection; absolute `pwsh` paths; credentials; execution-policy changes; or machine module paths.

## Standalone profile recipe

```yaml
name: PowerShell Development
components:
  - main
  - powershell
```

## Reused by

The optional PowerShell Development profile and future Windows-administration or module-publishing profiles.

## Portability classification

The current Command Explorer setting is portable. No advanced-only extension is currently approved.

## Platform concerns

Windows prefers PowerShell 7 in `platform/windows.jsonc`. Linux keeps Bash as default and exposes PowerShell only as an optional terminal profile. These defaults are not duplicated here.

## Machine concerns

Module paths, remoting endpoints, certificates, local executable paths, signing identities, and administration credentials remain private.

## Workspace concerns

Repository-specific PSScriptAnalyzer rules, Pester configuration, module paths, test tasks, publishing commands, and execution policy belong in the project.

## Performance concerns

The Microsoft PowerShell extension is loaded from Main for frequent everyday use. This component should contain only advanced settings or tools whose extra UI, indexing, startup cost, or background activity is justified during dedicated PowerShell work.

## Deferred decisions

PSScriptAnalyzer formatting ownership, project-specific Pester integration, module publishing, Azure administration tooling, and whether any advanced-only extensions earn placement here.
