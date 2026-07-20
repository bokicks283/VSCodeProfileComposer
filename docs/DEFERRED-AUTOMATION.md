# Automation status

## Implemented now

- The narrow artifact composer is implemented in `scripts/Compose-Profile.ps1`.
- It validates repository inputs and composes settings, extensions, keybindings, manifests, override reports, and validation reports under ignored `build/profiles/`.
- Composition is temporary-directory-first, validated before replacement, idempotent, and isolated from live VS Code user data.
- Platform and explicitly supplied ignored machine overlays are supported.
- Pester tests cover merge behavior, validation, safe replacement, and current core profiles.

## Current delivery state

- Settings Sync is the deployment mechanism.
- This repository is the canonical human-readable configuration and composition source.
- Manual VS Code profiles remain the runtime source of truth.
- Stable profiles may be exported and stored privately.
- Default already receives everyday shell-language support from Suggested Baseline.
- PowerShell Development is an optional advanced profile, not a sixth required daily profile.
- Database support is opt-in through explicit Database, SQL Server, MongoDB, Web + Database, or Python + Database recipes.
- Database connection details remain local or employer-managed and are not materialized by this repository.

## Still deferred

- create or update dedicated VS Code profiles through a supported, backup-first interface
- verify that database-enabled exports contain no saved connections or authentication state
- generate reviewed `.code-profile` exports
- compare repository design with live profile state
- synchronize changes back from VS Code into components
- provide GUI management
- integrate with Unreal Tool Suite

Automatic profile installation remains deferred until a supported VS Code CLI workflow is proven. Do not edit undocumented VS Code profile databases. Settings Sync remains the primary cross-machine delivery mechanism for active profiles.

## Remaining validation gate

Do not implement automation until Default, C++, Unreal, Web, and Python have been manually validated in representative workspaces.

Validate Database, SQL Server, and MongoDB separately in disposable or non-sensitive environments before relying on them.

Validate PowerShell Development separately when advanced module, testing, analysis, debugging, publishing, or administration workflows become active.

Do not add speculative installation scripts “for later.”
