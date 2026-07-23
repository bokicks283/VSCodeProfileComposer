# Automation status

## Implemented now

- The unified PowerShell 7 CLI is implemented in `scripts/ProfileComposer.ps1`; the two original entry scripts remain compatibility wrappers.
- It validates repository inputs, generates built-in Default settings under ignored `build/global/`, and composes named-profile settings, extensions, keybindings, manifests, override reports, and validation reports under ignored `build/profiles/`.
- Composition is temporary-directory-first, validated before replacement, idempotent, and isolated from live VS Code user data.
- Platform and explicitly supplied ignored machine overlays are supported.
- Named machine IDs under `machine/local/` can be listed and selected explicitly. Their values are generated only into the built-in Default/application artifact, automatically applied to every profile, and excluded from Settings Sync; private overlays remain outside Git.
- Reviewed `.code-profile` artifacts can be generated explicitly for manual import through VS Code.
- Exported resources are limited to composed settings, extensions, keybindings, profile identity, and an optional opaque UI-state seed captured from a manual export; VS Code owns live UI state after import.
- Pester tests cover CLI dispatch/errors, wrappers, merge behavior, validation, safe replacement, source rename/default/sync transactions, rollback, guarded live-profile guidance, automatic UI-state recipe selection, and current core profiles.
- `composer.jsonc` declares the shared default component, and the CLI safely normalizes or renames that ownership without introducing a dependency graph.
- A conservative read-only `Main` profile ownership audit is recorded under `docs/audits/`.
- The `vscode` command group can list profile names/opaque IDs read-only, open a verified existing profile with `code --profile`, compose guided import/replacement packages, and verify deletion targets without writing live storage.
- `capture-ui-state` can infer its recipe only when `code --status` yields exactly one recipe ID/display-name match; ambiguous or absent matches require an explicit recipe.
- `sync [<recipe>] <export>` transactionally reconciles a reviewed manual export into recipe-specific settings, extension, and keybinding deltas plus an ignored UI-state seed. It classifies nested values before planning, routes safe paths into a resolved ignored machine definition, rejects sensitive/private resources, and can reconcile explicit apply-to-all application settings while excluding Sync-ignored values from tracked global ownership.

## Current delivery state

- Manual `.code-profile` import is available for creating VS Code profiles from composed artifacts.
- Settings Sync remains the primary cross-machine delivery mechanism after a profile is imported.
- This repository is the canonical human-readable configuration and composition source.
- Live VS Code profiles remain the runtime source of truth for UI placement and other VS Code-owned state.
- `ProfileComposer.ps1 capture-ui-state [<profile-id>] <export-path>` can extract and retain only the opaque UI resource from a manually exported profile under ignored local data. Automatic recipe selection reads status text only and fails closed. `-UiStateProfile` reuses that copy-on-create starting point during composition. Direct live capture, layout parsing or merging, and continuing inheritance remain deferred.
- `ProfileComposer.ps1 sync [<profile-id>] <export-path>` is the reviewed reverse path for the repository-owned resources in that export. Flattened differences remain recipe-specific unless a human deliberately promotes them into a shared component.
- Stable profiles may be exported and stored privately.
- Main is the shared base and already provides everyday shell-language support to every profile.
- PowerShell Development is an optional advanced profile, not a sixth required daily profile.
- Database support is opt-in through explicit Database, SQL Server, MongoDB, Web + Database, or Python + Database recipes.
- Database connection details remain local or employer-managed and are not materialized by this repository.

## Still deferred

- unattended creation, replacement, or deletion of VS Code profiles (the supported Profiles editor remains the final confirmation surface)
- verify that database-enabled exports contain no saved connections or authentication state
- provide an opt-in, redacted general comparison report for arbitrary live profiles (the one-time `Main` audit is complete)
- automatically export the current profile without a manual Profiles-editor export
- infer or promote flattened live changes into shared components
- synchronize snippets, tasks, MCP definitions, or other resource classes not owned by the current repository schema
- provide GUI management
- integrate with Unreal Tool Suite

Automatic profile installation remains deferred until a supported VS Code CLI workflow is proven. Guided preparation and target verification are implemented; do not edit undocumented VS Code profile databases. Settings Sync remains the primary cross-machine delivery mechanism for active profiles.

## Remaining validation gate

Before treating generated profiles as production defaults, manually validate Main, C++, Unreal, Web, and Python in representative workspaces and review VS Code's import preview.

Validate Database, SQL Server, and MongoDB separately in disposable or non-sensitive environments before relying on them.

Validate PowerShell Development separately when advanced module, testing, analysis, debugging, publishing, or administration workflows become active.

Do not add speculative installation scripts “for later.”

Follow the [complete usage guide](USAGE.md) for the validation sequence, safe manual import, Settings Sync precautions, and routine maintenance workflow.
