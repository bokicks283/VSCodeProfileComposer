# Default

## Purpose

Adds the user's general daily-driver preferences and selected optional viewers, Git tools, API tooling, and Markdown helpers beyond the Suggested Baseline.

Because Suggested Baseline already owns basic PowerShell, Bash/Zsh shell-script, Windows batch, and general terminal support, Default can handle routine mixed-repository scripting without a profile switch.

## Belongs here

Cross-stack tools the user wants available in the normal Default profile but does not need in every focused profile.

## Does not belong here

Advanced PowerShell development behavior, operating-system terminal defaults, heavy language servers, Unreal tooling, database clients, Kubernetes/container tooling, machine paths, or workspace exclusions.

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

Settings and extension IDs are portable and contain no account state. Shell and terminal fundamentals come from Suggested Baseline.

## Platform concerns

Apply `platform/windows.jsonc` or `platform/linux.jsonc` manually as appropriate. Windows prefers PowerShell 7; Linux defaults to Bash.

## Machine concerns

Profile-specific sign-ins, AI provider state, Git credentials, absolute executable paths, PowerShell module paths, and remoting endpoints remain local.

## Workspace concerns

Enable GitHub Actions, Thunder Client, or other optional tools only where useful if startup measurements justify further isolation. Project-owned shell analysis or formatting rules remain in the repository.

## Performance concerns

GitLens and GitHub Actions were retained as optional tools, not baseline requirements. Measure them in large Unreal workspaces. Microsoft PowerShell remains a provisional baseline extension and should be revisited only if Default measurements show a meaningful cost.

## Deferred decisions

Containers, Kubernetes, database tools, advanced Markdown editors, SVG tooling, and project-management extensions remain deferred components.
