# Makefile

## Purpose

Portable Makefile project discovery, configuration, build, launch, and
compilation-database integration for native projects.

## Belongs here

Makefile-specific extensions and portable defaults that should be shared by
profiles explicitly targeting Makefile repositories.

## Does not belong here

General C/C++ language support, make executable paths, project-specific
targets, environment setup scripts, build logs, or UnrealBuildTool behavior.

## Standalone profile recipe

```yaml
name: C++
components:
  - main
  - cpp
  - makefile
```

## Reused by

The standalone C++ profile and future native Makefile profiles. Unreal does
not compose this component because UnrealBuildTool owns its build generation.

## Portability classification

The extension ID is portable. Make executable and environment discovery remain
outside this component.

## Platform concerns

Make implementations and environment setup differ by operating system.

## Machine concerns

Absolute make, compiler, SDK, and environment-script paths stay machine-local.

## Workspace concerns

Makefile location, configurations, targets, build logs, launch settings, and
pre/post-configuration scripts belong to the repository.

## Performance concerns

Makefile Tools activates when it finds a Makefile at a workspace root and may
run configuration or compilation-database discovery. Profiles that do not use
Makefiles should omit this component.

## Deferred decisions

No global make path, configuration, build target, or launch target is selected.
