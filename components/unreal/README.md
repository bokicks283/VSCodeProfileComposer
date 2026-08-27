# Unreal

## Purpose

Adds Unreal Engine-specific performance controls and lazy HLSL tooling on top
of the C++ and C# components. General documentation generation, semantic C++
IntelliSense, debugging, and C++ agent context are inherited from C++; C#
language support covers UnrealBuildTool build rules.

## Belongs here

Unreal-only extensions and portable settings validated across Unreal repositories.

## Does not belong here

General C/C++ settings, compiler paths, engine installation paths, project-generated-folder exclusions, repository docs bridges, or Blueprint tooling tied to one project.

## Standalone profile recipe

```yaml
name: Unreal Engine
components:
  - main
  - cpp
  - csharp
  - unreal
```

## Reused by

The Unreal Engine profile and future Unreal project variants.

## Portability classification

Extension IDs, the profile's Unreal shader file associations, and generic
Unreal directory names are portable. The component keeps normal cpptools
semantic IntelliSense enabled, but turns off automatic whole-file code analysis
and prevents C++, file-watcher, search, and Git repository discovery from
recursively scanning non-source Unreal trees.

## Platform concerns

Unreal toolchain and engine discovery differ by OS and remain outside this component.

## Machine concerns

Engine roots, Visual Studio toolchain paths, SDK paths, and local Unreal build settings stay machine-local.

## Workspace concerns

Project-specific generated paths, include paths, docs bridges, and team-shared
behavior belong in the workspace. Portable Unreal folder-name exclusions are
already in this component so a profile import receives them immediately. See
`workspace-examples/unreal.example.jsonc` when the repository should enforce
the same behavior independently of the selected personal profile.

UnrealBuildTool should generate a project-only workspace with
`VSCodeProjectFileGenerator.bIncludeEngineSource=false`. Engine headers remain
available through the generated compile commands and response files; adding the
engine installation as a second workspace folder causes VS Code, Git tooling,
and folder-activated extensions to traverse it independently.

Do not exclude `Intermediate` through `C_Cpp.files.exclude`: Unreal-generated
headers required by IntelliSense live there. The workspace example excludes it
from ordinary text search, but intentionally leaves it available to cpptools.

## Performance concerns

The archived audit recorded a usable window in seconds but more than seven
minutes of C++ indexing, plus GitLens repository discovery lasting roughly one
minute per broad workspace root. The profile settings target those background
costs without lowering `C_Cpp.workspaceParsingPriority`, disabling semantic
IntelliSense, or removing engine headers. HLSL Tools activates only when an
`.hlsl`, `.usf`, or `.ush` file is opened. The startup-activated UVCH helper is
not required: its header/source switching and browser conveniences overlap
existing tools and can be installed later only if a measured workflow needs it.

## Deferred decisions

Blueprint tooling, Unreal Header Tool integration, workspace-specific docs
bridges, and a validated Unreal INI language solution.

The C++ profile's July 31 functional test also left these Unreal-specific items
for this component/workspace phase:

- verify that project, engine, and user/shared `DerivedDataCache` locations are
  excluded from cpptools browsing after the Unreal settings are active;
- measure the discovered-file count after one database reset, rather than
  rebuilding the unfiltered database first;
- validate cpptools 1.33.5 or newer, because 1.32.2 crashed and left completion
  providers disconnected in the representative UE 5.8 workspace;
- consider clangd only as an explicit alternative IntelliSense provider test,
  not as an additional provider running alongside cpptools.
