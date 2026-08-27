# C#

## Purpose

Portable C# language support for profiles that edit .NET source, including
UnrealBuildTool `.Build.cs` and `.Target.cs` rules.

## Belongs here

The base Microsoft C# language extension and portable C# editor behavior that
is useful across more than one C#-capable profile.

## Does not belong here

Unreal-specific build-rule project generation, C# Dev Kit project-management
features, machine SDK paths, solution selection, or repository build policy.

## Standalone profile recipe

```yaml
name: C#
components:
  - main
  - csharp
```

## Reused by

The Unreal Engine profile and future .NET, Unity, tooling, or modding profiles.

## Portability classification

The extension ID is portable. Project and solution files remain workspace
owned, while SDK and runtime paths remain machine-local.

## Platform concerns

.NET runtime, SDK, and MSBuild availability differ by operating system. The
component does not select or install a system SDK.

## Machine concerns

Absolute .NET, MSBuild, Visual Studio, Mono, and Unreal Engine paths stay
machine-local.

## Workspace concerns

Projects, solutions, target frameworks, analyzers, formatting policy, and any
UnrealBuildTool-aware project context belong to the repository or its generated
workspace tooling.

## Performance concerns

The C# language server obtains its best semantic context from a `.csproj` or
solution. The base extension is included without C# Dev Kit so profiles receive
language support without adding its solution-management surface. Unreal
build-rule types may remain unresolved until project tooling supplies an
UnrealBuildTool-aware C# project context.

## Deferred decisions

C# Dev Kit, formatter/analyzer policy, test tooling, and generation of a small
UnrealBuildTool-aware project or solution remain measurement- and
workspace-dependent.
