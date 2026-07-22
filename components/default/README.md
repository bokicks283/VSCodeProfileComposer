# Default

## Purpose

Default is the shared foundation for every profile. It combines portable editor and terminal behavior with the user's general daily-driver extensions and preferences, so focused profiles add only their language, engine, or database concerns.

It supports everyday editing of PowerShell, Bash/Zsh shell scripts, Windows batch files, Markdown, XML, YAML, TOML, environment files, and common repository content without requiring a profile switch.

## Belongs here

- portable editor, Git, source-control, terminal, and workbench behavior used across profiles;
- broadly useful repository, format, navigation, diagnostics, Markdown, viewer, and API tools;
- built-in shell and batch file associations;
- the Microsoft PowerShell extension for normal scripting and occasional debugging;
- extensions and preferences the user expects in every profile;
- portable editor, notebook, panel, Markdown, and spell-checker keybindings expected in every profile.

## Does not belong here

Advanced PowerShell development behavior, operating-system terminal defaults, heavy language-specific tooling, Unreal-only tools, database clients, vendor-specific database extensions, Kubernetes/container tooling, machine paths, credentials, saved connections, or workspace policy.

## Standalone profile recipe

```yaml
name: Default
components:
  - default
```

## Reused by

Every recipe begins with `default`. Focused components add to this shared base rather than inheriting from another profile.

## Portability classification

Settings and extension IDs are portable and contain no account state. Settings intentionally applied to every profile are owned by `global/settings.jsonc`, not duplicated here. The unreliable portable `todo-tree.ripgrep.ripgrep: "rg"` value is intentionally absent; machines that require it must provide a confirmed absolute path through an ignored named machine overlay.

`keybindings.jsonc` is the canonical shared keybinding source. It preserves explicit removal entries alongside replacement shortcuts so VS Code does not reactivate displaced defaults. Extension-specific bindings belong here only when the owning extension is also part of Default.

## Platform concerns

Compose with `-Platform windows` or `-Platform linux` as appropriate. Windows terminal selection belongs in `platform/windows.jsonc`; Linux terminal selection belongs in `platform/linux.jsonc`. Default does not choose an operating-system shell.

## Machine concerns

Profile sign-ins, provider state, Git credentials, absolute executable paths, compiler or SDK paths, database connections, PowerShell module paths, and remoting endpoints remain local.

## Workspace concerns

Generated folders, project excludes, formatter and linter policy, PSScriptAnalyzer/Pester rules, build tasks, include paths, schema policy, and team connection behavior belong in workspace settings.

## Performance concerns

This component deliberately favors a consistent base experience across all profiles. Measure shared extensions in representative large workspaces; move a tool into a focused component only when there is a clear ownership reason or meaningful measured cost.

Database and heavy language-specific extensions remain outside Default because they are unnecessary for every profile and may add language servers, background services, connection explorers, indexing, or retained authentication state.

## Deferred decisions

Whether INI-specific validation is safe for Unreal syntax, whether additional shell checking is justified, and whether future measurements show that any shared extension belongs in a focused component.
