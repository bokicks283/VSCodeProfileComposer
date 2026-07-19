# Deferred automation

## Current state

- Settings Sync is the deployment mechanism.
- This repository is the human-readable configuration design and planning system.
- Manual VS Code profiles remain the runtime source of truth.
- Stable profiles may be exported and stored privately.

## Possible future work

After the six immediate profiles are stable, automation may:

- compose settings, extensions, and genuine component-owned keybindings
- detect duplicate or conflicting settings
- create or update VS Code profiles
- validate platform and machine overlays
- generate reviewed `.code-profile` exports
- compare repository design with live profile state

## Gate

Do not implement automation until Default, C++, Unreal, PowerShell, Web, and Python have been manually validated in representative workspaces.

Do not add scripts “for later.”
