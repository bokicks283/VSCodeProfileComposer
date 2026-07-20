# Deferred automation

## Current state

- Settings Sync is the deployment mechanism.
- This repository is the human-readable configuration design and planning system.
- Manual VS Code profiles remain the runtime source of truth.
- Stable profiles may be exported and stored privately.
- Default already receives everyday shell-language support from Suggested Baseline.
- PowerShell Development is an optional advanced profile, not a sixth required daily profile.
- Database support is opt-in through explicit Database, SQL Server, MongoDB, Web + Database, or Python + Database recipes.
- Database connection details remain local or employer-managed and are not materialized by this repository.

## Possible future work

After the five core profiles are stable, automation may:

- compose settings, extensions, and genuine component-owned keybindings
- detect duplicate or conflicting settings
- create or update VS Code profiles
- validate platform and machine overlays
- verify that database-enabled exports contain no saved connections or authentication state
- generate reviewed `.code-profile` exports
- compare repository design with live profile state

## Gate

Do not implement automation until Default, C++, Unreal, Web, and Python have been manually validated in representative workspaces.

Validate Database, SQL Server, and MongoDB separately in disposable or non-sensitive environments before relying on them.

Validate PowerShell Development separately when advanced module, testing, analysis, debugging, publishing, or administration workflows become active.

Do not add scripts “for later.”
