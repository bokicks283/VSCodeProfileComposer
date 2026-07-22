# Unreal

## Purpose

Adds Unreal Engine-specific navigation, documentation generation, C++ agent context, and optional HLSL tooling on top of the C++ component.

## Belongs here

Unreal-only extensions and portable settings validated across Unreal repositories.

## Does not belong here

General C/C++ settings, compiler paths, engine installation paths, project-generated-folder exclusions, repository docs bridges, or Blueprint tooling tied to one project.

## Standalone profile recipe

```yaml
name: Unreal Engine
components:
  - default
  - cpp
  - unreal
```

## Reused by

The Unreal Engine profile and future Unreal project variants.

## Portability classification

Extension IDs are portable. Settings are intentionally minimal because the reviewed source currently contains only an Unreal planning stub.

## Platform concerns

Unreal toolchain and engine discovery differ by OS and remain outside this component.

## Machine concerns

Engine roots, Visual Studio toolchain paths, SDK paths, and local Unreal build settings stay machine-local.

## Workspace concerns

Generated-folder exclusions, `.trunk` cache exclusions, project include paths, docs bridges, and team-shared project behavior belong in the workspace. See `workspace-examples/unreal.example.jsonc`.

## Performance concerns

HLSL Tools and C++ Dev Tools are optional in practice; measure their activation in the real Unreal workspace before treating them as mandatory.

## Deferred decisions

Blueprint tooling, Unreal Header Tool integration, workspace-specific docs bridges, and a validated Unreal INI language solution.
