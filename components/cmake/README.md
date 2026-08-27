# CMake

## Purpose

Portable CMake project configuration, build, debug, task, preset, language,
and CTest integration for native projects.

## Belongs here

CMake-specific extensions and portable CMake workflow defaults that should be
shared by profiles explicitly targeting CMake repositories.

## Does not belong here

General C/C++ language support, compiler or CMake executable paths, project
presets, toolchain files, build directories, or UnrealBuildTool behavior.

## Standalone profile recipe

```yaml
name: C++
components:
  - main
  - cpp
  - cmake
```

## Reused by

The standalone C++ profile and future native CMake profiles. Unreal does not
compose this component because UnrealBuildTool owns its build generation.

## Portability classification

The extension ID is portable. CMake executable and toolchain discovery remain
outside this component.

## Platform concerns

CMake generators and compiler discovery differ by operating system.

## Machine concerns

Absolute CMake, compiler, SDK, Ninja, and toolchain paths stay machine-local.

## Workspace concerns

`CMakePresets.json`, toolchain selection, configure arguments, build
directories, cache policy, and test configuration belong to the repository.

## Performance concerns

CMake Tools activates for CMake workflows and can perform project discovery,
configuration, code-model queries, and test discovery. Profiles that do not
use CMake should omit this component.

## Deferred decisions

No global generator, kit, preset, or automatic configure policy is selected.
