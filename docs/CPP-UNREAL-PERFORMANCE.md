# C++ and Unreal performance settings

This is the repository decision record for keeping the C++ and Unreal profiles
responsive without disabling engine IntelliSense. It uses the archived
`VSCodeOptimizationAudit` evidence; it does not require repeating the expensive
benchmark before applying these reversible settings.

## Confirmed archived symptoms

- The VS Code window became usable in about three seconds.
- Most visible extensions took about 1 minute 22 seconds to settle, while an
  unrelated Java/Gradle extension continued for almost three minutes.
- C/C++ indexing was still running after seven minutes, and a separate idle
  note recorded more than ten minutes before C++ files finished loading.
- The audited workspace contained both the game repository and the complete
  UE 5.8 installation.
- C/C++ diagnostics showed the correct project MSVC compiler and generated
  compile commands, but the browse database received large project and engine
  include-path sets.
- GitLens logged repository discovery near 95 seconds for the project root and
  65 seconds for the engine workspace root.
- A July 31 follow-up with cpptools 1.32.2 reproduced a language-server crash
  and disconnected completion providers. Switching the C++ profile to cpptools
  1.33.5 restored class-scope completion without changing the generated compile
  commands.
- The working 1.33.5 diagnostic still reported roughly 2.7 GB for one Unreal
  translation unit. It correctly mapped project and engine headers through the
  generated response file, so that cost is an Unreal workload finding rather
  than a missing general C++ configuration.

The new composed profiles already remove the old Java/Gradle extension surface.
The remaining controls therefore focus on workspace breadth, cpptools tag
parsing, and repository discovery.

## Required configuration by owner

| Owner | Setting or action | Reason |
|---|---|---|
| C++ component | `C_Cpp.default.browse.limitSymbolsToIncludedHeaders=true` | Parse headers reached by workspace source instead of every file in every browse path |
| C++ component | `C_Cpp.exclusionPolicy=checkFolders` | cpptools documents this as the faster initialization policy when exclusions are folder-only |
| C++ component | `C_Cpp.workspaceSymbols=All` | Preserve general-library workspace-symbol discovery; this setting does not control semantic completion or debugging |
| Unreal component | `C_Cpp.codeAnalysis.runAutomatically=false` | Avoid automatic whole-file analysis on open/save; manual analysis remains available |
| Unreal component/workspace | `C_Cpp.files.exclude` for `Binaries`, `Content`, `DerivedDataCache`, `Saved`, `.trunk`, and `node_modules` | Keep non-C++ trees out of the code-navigation database, including paths outside the workspace |
| Unreal component/workspace | Hide `.uasset`/`.umap`, exclude cache/generated trees from watchers and search, and associate `.usf`/`.ush` with HLSL | Avoid binary-asset and generated-tree background work while lazily enabling shader support |
| Unreal component/workspace | Built-in Git detection limited to open editors with shallow repository scanning | Avoid recursive Git discovery across large Unreal roots |
| Workspace | Optional repository copy of `workspace-examples/unreal.example.jsonc` | Enforce the personal profile's protections for teammates using a different profile |
| UnrealBuildTool | `VSCodeProjectFileGenerator.bIncludeEngineSource=false` | Keep the full engine installation out of the workspace root list |
| Project `.vscode` | Generated MSVC `compilerPath` and project `compileCommands` | Preserve accurate compilation context and engine header navigation |

## Why engine IntelliSense still works

The engine does not need to be a workspace folder. UnrealBuildTool's generated
compile commands and response files contain the engine include directories,
defines, forced includes, and compiler context used by each project translation
unit. cpptools can therefore open included engine headers and provide semantic
completion/definition navigation without asking VS Code, Git, search, and every
folder-activated extension to treat the entire engine installation as a root.

`browse.limitSymbolsToIncludedHeaders=true` still permits headers directly or
indirectly used by project source. The tradeoff is intentional: **Go to Symbol
in Workspace** no longer tries to be a complete catalog of unrelated engine
symbols. Direct include navigation, definitions, completion, and engine headers
used by the project remain available.

The generic C++ profile intentionally does not exclude Unreal directory names.
When it is used to inspect an Unreal project, live indexing may therefore enter
`DerivedDataCache` and other framework-specific trees. That observation is not
a reason to place Unreal exclusions in the reusable C++ component. Apply and
verify those exclusions when composing the Unreal profile or its shared
workspace settings.

The Unreal profile hides binary `.uasset` and `.umap` files from Explorer but
does not hide the complete `Content` tree. Text-based project files under
`Content` therefore remain addressable even though ordinary search and file
watching skip that high-volume tree. Use VS Code's excluded-files toggle for an
exceptional direct inspection of a hidden binary asset name.

The July 31 1.33.5 diagnostic did not contain the live `DerivedDataCache` path
or a final workspace-parsing file count. During Unreal-profile verification,
capture the exact path from the C/C++ output/status and confirm that project,
engine, and user/shared cache variants are all covered by portable glob rules.

## Why `Intermediate` is not a cpptools exclusion

Unreal Header Tool places `.generated.h` headers under `Intermediate`. Excluding
that tree from `C_Cpp.files.exclude` can create missing-generated-header errors
and incomplete reflection-aware IntelliSense. The template excludes
`Intermediate` from ordinary text search only. If watcher activity remains a
problem, test a narrower project-specific pattern rather than globally removing
all generated headers from observation.

## Settings deliberately not used

- Lower `C_Cpp.workspaceParsingPriority`: cpptools defines the levels as roughly
  100/75/50/25 percent CPU. Lower values insert sleeps, improving foreground CPU
  availability but extending the time until parsing completes.
- `C_Cpp.intelliSenseEngine=Tag Parser` or `disabled`: both sacrifice semantic
  IntelliSense, which is the feature this profile must preserve.
- Excluding `Engine/Source`: this would reduce engine navigation rather than
  solving workspace ownership correctly.
- Disabling the browse database or IntelliSense cache: that can improve one
  cold phase while making later navigation and warm reloads worse.
- A portable compiler path or fixed memory limit: compiler installations and
  available memory vary by machine. Keep these in machine schema 2 or generated
  project configuration.

## Apply and verify without a new benchmark

1. Compose/import the updated C++ or Unreal profile.
2. Ensure the UBT machine/project configuration contains
   `bIncludeEngineSource=false`, then regenerate the VS Code project.
3. Open the generated `.code-workspace` as text and confirm its `folders` array
   contains the game repository only. The current `AmericanCartel` workspace
   was observed to contain the UE 5.8 root again, so this check matters after
   every regeneration until UETools owns the setting sync.
4. Merge the reviewed entries from
   `workspace-examples/unreal.example.jsonc` into the generated workspace through
   the UETools settings-sync workflow.
5. Confirm `.vscode/c_cpp_properties.json` selects the MSVC compiler and the
   project-specific `compileCommands_AmericanCartel.json`.
6. Launch normally and judge usability. Do not wait for a formal benchmark:
   check that unrelated extensions settle quickly, project completion works,
   and an included engine symbol can navigate to its definition.

If the profile remains near ten minutes after these controls, compare only the
new symptom against the archived audit before adding machine CPU/memory/cache
tuning or replacing cpptools with clangd.
