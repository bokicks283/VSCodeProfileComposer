# Main profile health check — 2026-07-29

This was a repository health check plus a read-only comparison of the live
stable VS Code `Main` profile. No live profile, extension, UI state, account
state, Application Settings value, or Settings Sync state was changed.

## Repository result

- strict validation passes for 9 components and 11 recipes;
- strict Windows validation passes with the ignored `excalibur117-w` machine
  definition;
- the documentation validator passes every Markdown file, help topic, router
  schema, link, command, parameter, and mode;
- all 118 isolated Pester tests pass;
- Main composes successfully with 53 named-profile settings, 36 declared
  extension identifiers, 22 keybindings, the configured Main UI seed, and a
  separate 54-setting Application Settings artifact.

The health check corrected three source issues before producing that result:

- removed the machine-owned `todo-tree.ripgrep.ripgrep` key from the canonical
  global apply-to-all list; the composer adds it dynamically when a machine
  overlay supplies its value;
- removed a stale Main profile sidecar that duplicated the SQL Server
  IntelliSense keybinding already owned by `components/sql-server`;
- made profile and component rename transactions update matching managed
  ownership-router destinations.

## Read-only live comparison

The generated Application Settings artifact matches all 54 corresponding live
Application Settings values exactly.

The live named Main profile matches every one of the 53 generated setting
values and all 22 generated keybindings. It retains two stale profile-local
entries that the repository no longer owns there:

- `todo-tree.ripgrep.ripgrep`, whose effective value belongs only in the
  ignored machine definition and built-in Default/Application Settings;
- `mssql.rebuildIntelliSenseCache`, whose binding belongs only to the SQL
  Server component.

The generated Main artifact excludes both stale entries. Remove them during
the next reviewed Main re-import or manual live-profile cleanup; the composer
does not write VS Code's private profile storage.

All declared Main extensions are available. VS Code 1.130 supplies
`github.copilot-chat` as the built-in GitHub Copilot extension, so it is not
reported by `code --profile Main --list-extensions`. The live-only
`github.remotehub`, `ms-vscode.azure-repos`, and
`ms-vscode.remote-repositories` entries are support/dependency extensions and
are not promoted into Main ownership.

## Unreal handoff

With Main healthy at the repository boundary, the Unreal Engine artifact was
generated from `main + cpp + unreal`. It contains 60 settings, 41 extension
identifiers, 22 keybindings, the configured Main UI seed, and no embedded
machine path. Manual import preview and validation in the primary Unreal
workspace remain the next runtime gate.
