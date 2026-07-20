# Default

## Purpose

Adds the user's general daily-driver preferences and selected optional viewers, Git tools, API tooling, and Markdown helpers beyond the Suggested Baseline.

Because Suggested Baseline already owns basic PowerShell, Bash/Zsh shell-script, Windows batch, and general terminal support, Default can handle routine mixed-repository scripting without a profile switch.

## Belongs here

Cross-stack tools the user wants available in the normal Default profile but does not need in every focused profile.

## Does not belong here

Advanced PowerShell development behavior, operating-system terminal defaults, heavy language servers, Unreal tooling, database clients, database language servers, connection explorers, vendor-specific database extensions, Kubernetes/container tooling, machine paths, or workspace exclusions.

## Standalone profile recipe

```yaml
name: Default
components:
  - suggested-baseline
  - default
```

## Reused by

Only the explicit Default recipe. Focused profiles choose their own components rather than inheriting Default.

## Portability classification

Settings and extension IDs are portable and contain no account state. Shell and terminal fundamentals come from Suggested Baseline. Database support is added only through explicit database components.

## Platform concerns

Compose with `-Platform windows` or `-Platform linux` as appropriate. Windows prefers PowerShell 7; Linux defaults to Bash.

## Machine concerns

Profile-specific sign-ins, AI provider state, Git credentials, absolute executable paths, database connections, PowerShell module paths, and remoting endpoints remain local.

## Workspace concerns

Enable GitHub Actions, Thunder Client, or other optional tools only where useful if startup measurements justify further isolation. Project-owned shell analysis, formatting rules, and database connection policy remain in the repository or employer-managed tooling.

## Performance concerns

GitLens and GitHub Actions were retained as optional tools, not baseline requirements. Measure them in large Unreal workspaces. Microsoft PowerShell remains a provisional baseline extension and should be revisited only if Default measurements show a meaningful cost.

Default intentionally excludes database tooling because ordinary daily editing does not require database background services, language servers, or connection UI.

## Deferred decisions

Containers, Kubernetes, advanced Markdown editors, SVG tooling, and project-management extensions remain deferred components.
