# C++

## Purpose

Portable general C and C++ language intelligence, formatting ownership, navigation, semantic highlighting, and debugging support.

## Belongs here

`C_Cpp.*`, `[c]`, `[cpp]`, `[cuda-cpp]`, and general C/C++ extensions.

## Does not belong here

Unreal-only settings, Unreal generated-folder exclusions, project include paths, compiler installation paths, CMake/Make settings for repositories that do not use those build systems, or machine memory tuning.

## Standalone profile recipe

```yaml
name: C++
components:
  - default
  - cpp
```

## Reused by

C++ and Unreal Engine profiles; future native CMake, embedded, and C++ game profiles may also reuse it.

## Portability classification

All active settings are portable and use the approved Microsoft C/C++ formatter already present in the reviewed source.

## Platform concerns

Compiler discovery may differ by OS, but compiler paths are not committed here.

## Machine concerns

`C_Cpp.default.compilerPath`, SDK paths, `C_Cpp.intelliSenseMemoryLimit`, and other hardware-specific tuning belong in `machine/local/`.

## Workspace concerns

Include paths, compile commands, toolchains, generated-folder exclusions, and CMake configuration belong in the repository.

## Performance concerns

The reviewed 6144 MB IntelliSense limit and full workspace-symbol tuning were excluded from portable settings because they may be inappropriate on another machine or a very large Unreal workspace.

## Deferred decisions

CodeLLDB, CMake Tools, Makefile Tools, and compiler-specific formatters remain optional or project-specific.
