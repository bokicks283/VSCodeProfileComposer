# Automation status

## Implemented now

- The unified PowerShell 7 CLI is implemented in `scripts/ProfileComposer.ps1`; the two original entry scripts remain compatibility wrappers.
- It validates repository inputs, generates built-in Default settings under ignored `build/global/`, and composes named-profile settings, extensions, keybindings, manifests, override reports, and validation reports under ignored `build/profiles/`.
- Composition is temporary-directory-first, validated before replacement, idempotent, and isolated from live VS Code user data.
- Platform and explicitly supplied ignored machine overlays are supported.
- Named machine IDs under `machine/local/` can be listed and selected explicitly. Their values are generated only into the built-in Default/application artifact, automatically applied to every profile, and excluded from Settings Sync; private overlays remain outside Git.
- Reviewed `.code-profile` artifacts can be generated explicitly for manual import through VS Code.
- Exported resources are limited to composed settings, extensions, keybindings, profile identity, and an optional opaque UI-state seed captured from a manual export; VS Code owns live UI state after import.
- Pester tests cover CLI dispatch/errors, wrappers, merge behavior, validation, safe replacement, source rename/default transactions, rollback, and current core profiles.
- `composer.jsonc` declares the shared default component, and the CLI safely normalizes or renames that ownership without introducing a dependency graph.
- A conservative read-only `Main` profile ownership audit is recorded under `docs/audits/`; no general live comparison or reverse-write command was added.

## Current delivery state

- Manual `.code-profile` import is available for creating VS Code profiles from composed artifacts.
- Settings Sync remains the primary cross-machine delivery mechanism after a profile is imported.
- This repository is the canonical human-readable configuration and composition source.
- Live VS Code profiles remain the runtime source of truth for UI placement and other VS Code-owned state.
- `Save-ProfileUiState.ps1` can extract and retain only the opaque UI resource from a manually exported profile under ignored local data. `-UiStateProfile` reuses that copy-on-create starting point. Direct live capture, layout parsing or merging, and continuing inheritance remain deferred.
- Stable profiles may be exported and stored privately.
- Default is the shared base and already provides everyday shell-language support to every profile.
- PowerShell Development is an optional advanced profile, not a sixth required daily profile.
- Database support is opt-in through explicit Database, SQL Server, MongoDB, Web + Database, or Python + Database recipes.
- Database connection details remain local or employer-managed and are not materialized by this repository.

## Still deferred

- create or update dedicated VS Code profiles through a supported, backup-first interface
- verify that database-enabled exports contain no saved connections or authentication state
- provide an opt-in, redacted general comparison report for arbitrary live profiles (the one-time `Main` audit is complete)
- synchronize changes back from VS Code into components
- provide GUI management
- integrate with Unreal Tool Suite

Automatic profile installation remains deferred until a supported VS Code CLI workflow is proven. Do not edit undocumented VS Code profile databases. Settings Sync remains the primary cross-machine delivery mechanism for active profiles.

## Remaining validation gate

Before treating generated profiles as production defaults, manually validate Default, C++, Unreal, Web, and Python in representative workspaces and review VS Code's import preview.

Validate Database, SQL Server, and MongoDB separately in disposable or non-sensitive environments before relying on them.

Validate PowerShell Development separately when advanced module, testing, analysis, debugging, publishing, or administration workflows become active.

Do not add speculative installation scripts “for later.”

Follow the [complete usage guide](USAGE.md) for the validation sequence, safe manual import, Settings Sync precautions, and routine maintenance workflow.
