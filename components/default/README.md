# Default

## Purpose

Adds the user's general daily-driver preferences and selected optional viewers, Git tools, API tooling, and Markdown helpers beyond the Suggested Baseline.

## Belongs here

Cross-stack tools the user wants available in the normal Default profile but does not need in every focused profile.

## Does not belong here

Language servers, Unreal tooling, database clients, Kubernetes/container tooling, machine paths, or workspace exclusions.

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

Settings and extension IDs are portable and contain no account state.

## Platform concerns

Apply `platform/windows.jsonc` or `platform/linux.jsonc` manually as appropriate.

## Machine concerns

Profile-specific sign-ins, AI provider state, Git credentials, and absolute executable paths remain local.

## Workspace concerns

Enable GitHub Actions, Thunder Client, or other optional tools only where useful if startup measurements justify further isolation.

## Performance concerns

GitLens and GitHub Actions were retained as optional tools, not baseline requirements. Measure them in large Unreal workspaces.

## Deferred decisions

Containers, Kubernetes, database tools, advanced Markdown editors, SVG tooling, and project-management extensions remain deferred components.
