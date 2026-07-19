# Component guidelines

## DRY ownership

A setting or extension belongs in the smallest reusable component that fully explains why it exists. Larger profiles reference that component rather than copying it.

## Standalone usability

Every focused component must work in a recipe with `suggested-baseline`.

## Settings ownership

- General editor behavior → Suggested Baseline
- Personal cross-stack optional behavior → Default
- General C/C++ → C++
- Unreal-only → Unreal
- PowerShell-only → PowerShell
- Browser/Web → Web
- General Python → Python
- OS preference → Platform
- Personal executable or SDK path → Machine
- Repository policy → Workspace

## Extension ownership

Avoid extension-pack wrappers and duplicate tools. Keep framework-specific and heavy extensions out of broad components unless the MVP explicitly needs them.

## Dependencies

Document conceptual dependencies in profile recipes. Do not implement inheritance or hidden dependencies.

## Platform and machine boundaries

Executable names may be portable when `PATH` lookup is supported. Absolute paths are machine-local.

## Workspace boundaries

Formatters, linters, generated-folder exclusions, toolchains, include paths, and framework enablement become workspace settings when the repository owns the decision.

## Conflict avoidance

Do not assign multiple default formatters to one language. Do not enable overlapping linters by default. Record unresolved ownership rather than inventing a replacement.

## Performance

Any extension with wildcard activation, deep scanning, language servers, project discovery, or background indexing must justify its component and be measured in representative workspaces.
