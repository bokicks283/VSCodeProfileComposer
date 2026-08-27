# Workspace examples

Workspace settings are for genuine repository or team behavior. Some portable
Unreal exclusions also exist in the personal Unreal profile; copying the
example into a workspace makes those protections independent of which profile
a teammate selects.

Typical workspace-owned behavior includes:

- generated-folder and file-watcher exclusions
- project include paths and compile commands
- repository-selected formatters and linters
- project SDK/toolchain paths when team-shareable
- extension enablement tied to repository technology
- Unreal docs bridges or project-owned commands

Copy relevant values into a repository `.vscode/settings.json` or `.code-workspace` file. Do not apply the Unreal example globally.

The Unreal example deliberately separates three scopes:

- `C_Cpp.files.exclude` limits the cpptools code-navigation database without
  hiding folders from Explorer;
- `files.exclude` hides generated directories and binary Unreal assets while
  preserving text files under `Content`;
- `files.watcherExclude` and `search.exclude` limit general VS Code background
  work;
- Built-in Git settings prevent recursive repository discovery.

`Intermediate` is excluded from ordinary search but not from cpptools or the
file watcher because Unreal-generated `.generated.h` headers live there. The
highest-impact structural setting is outside this JSON: configure UnrealBuildTool
with `VSCodeProjectFileGenerator.bIncludeEngineSource=false` so regeneration
does not add the engine installation as a second workspace root. Compile
commands still provide engine include paths for IntelliSense.
