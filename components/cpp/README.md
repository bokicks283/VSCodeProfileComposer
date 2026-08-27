# C++

## Purpose

Portable general C and C++ language intelligence, formatting ownership,
navigation, semantic highlighting, debugging, documentation comments, and
agent-facing symbol tools.

## Belongs here

`C_Cpp.*`, `[c]`, `[cpp]`, `[cuda-cpp]`, and general C/C++ extensions that
remain useful regardless of the project's build system.

## Does not belong here

Unreal-only settings, Unreal generated-folder exclusions, project include
paths, compiler installation paths, CMake/Make workflow extensions or settings,
or machine memory tuning.

## Standalone profile recipe

```yaml
name: C++
components:
  - main
  - cpp
  - cmake
  - makefile
```

## Reused by

C++ and Unreal Engine profiles; future native CMake, embedded, and C++ game
profiles may also reuse it. Build-system components are selected separately by
each profile recipe.

## Portability classification

All active settings are portable and use the approved Microsoft C/C++ formatter already present in the reviewed source.

## Platform concerns

Compiler discovery may differ by OS, but compiler paths are not committed here.

## Machine concerns

`C_Cpp.default.compilerPath`, SDK paths, `C_Cpp.intelliSenseMemoryLimit`, and other hardware-specific tuning belong in `machine/local/`.

## Workspace concerns

Include paths, compile commands, toolchains, generated-folder exclusions, and CMake configuration belong in the repository.

## Performance concerns

The component limits browse-database symbols to headers included by workspace
source, uses the faster folder-only exclusion policy, keeps workspace-symbol
queries on `All`, and does not request word-based suggestions from every open
document. `All` preserves general-library symbol discovery for the reusable C++
profile; it controls workspace-symbol query results, not semantic completion or
debugger access. Framework profiles may narrow their browse database through
framework- or workspace-owned exclusions without changing this general default.

Compiler paths, compile commands, workspace parsing priority, concurrency,
cache sizing, and memory limits remain workspace- or machine-owned because
their correct values depend on the project and computer. In particular, the
reviewed 6144 MB IntelliSense limit remains machine-specific. Lowering
`C_Cpp.workspaceParsingPriority` is not a startup optimization: it reduces CPU
use by inserting sleeps and therefore increases the time required to finish
background parsing.

## Deferred decisions

CodeLLDB, compiler-specific formatters, and test-framework explorers remain
optional or project-specific. The standalone C++ recipe adds the focused CMake
and Makefile components, while Unreal intentionally omits them.
