# Suggested Baseline

## Purpose

A lightweight daily driver for repository navigation, Git/GitHub work, common configuration formats, basic source browsing, general terminal behavior, and routine shell-language work across mixed repositories and machines.

It supports everyday editing of:

```text
.ps1  .psm1  .psd1
.sh   .bash  .zsh
.bat  .cmd
```

## Belongs here

Portable editor and terminal behavior, broadly useful low-overhead format/repository extensions, built-in shell and batch file associations, and the Microsoft PowerShell extension for normal scripting, navigation, formatting commands, and occasional debugging.

## Does not belong here

PowerShell module publishing, Command Explorer, dedicated Pester/PSScriptAnalyzer workflow, Azure administration tooling, heavy language ecosystems, database clients, container tooling, SDK managers, framework scanners, compiler paths, credentials, or project exclusions.

## Standalone profile recipe

```yaml
name: Suggested Baseline
components:
  - suggested-baseline
```

## Reused by

Every profile in `profiles/`.

## Portability classification

All active settings are portable. Shell associations use VS Code language IDs, terminal behavior contains no OS-specific default selection, and `todo-tree.ripgrep.ripgrep` uses the executable name `rg`; a machine may override it with an absolute path.

## Platform concerns

Windows terminal selection belongs in `platform/windows.jsonc`; Linux terminal selection belongs in `platform/linux.jsonc`. The baseline does not choose an operating-system default shell.

## Machine concerns

The current Windows machine requires a machine-local absolute Todo Tree ripgrep path. The real personal path is intentionally excluded from this public repository. PowerShell executable paths, module paths, and remoting endpoints also remain local when they cannot be resolved portably.

## Workspace concerns

Generated folders, repository-specific excludes, PSScriptAnalyzer rules, module paths, test tasks, and team-owned shell formatting policy belong in workspace settings.

## Performance concerns

The Microsoft PowerShell extension is baseline-owned provisionally because it is frequently used, the source audit classified it as cross-profile, and its recorded activation events are tied to PowerShell language/debug/commands rather than eager startup. No reliable activation-time measurement was found, so this placement must be revisited if later Default measurements show a meaningful cost.

Project Manager, CODEOWNERS, All Autocomplete, Shift That, and Path Intellisense remain outside this baseline because they still require repair or isolated measurement.

## Deferred decisions

Whether INI-specific validation is safe for Unreal syntax, whether an additional shell-checking extension is justified, and whether future measurements require moving Microsoft PowerShell back to the advanced component.
