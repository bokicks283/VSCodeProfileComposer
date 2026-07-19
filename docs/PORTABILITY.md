# Portability

## Portable settings

Portable components contain editor preferences, language behavior, extension behavior, and executable names that can be resolved through `PATH`.

They must not contain usernames, home paths, drive-specific SDK paths, credentials, tokens, database secrets, or unsafe device tuning.

## Platform settings

`platform/windows.jsonc` and `platform/linux.jsonc` hold reusable OS-specific preferences.

## Machine-local settings

Real machine values live under ignored `machine/local/`. Committed examples use placeholders only.

## Workspace settings

Project behavior belongs in `.vscode/settings.json`, `.code-workspace`, or a reviewed example. Unreal generated folders and file watchers are workspace concerns, not C++ defaults.

## Secrets policy

Never commit:

- access tokens or API keys
- passwords or connection strings
- private hosts, database profiles, or SSH material
- extension account state
- exported profile files before inspection

## Settings Sync workflow

```text
Install VS Code
→ sign in
→ enable Settings Sync
→ enable profile synchronization
→ select the required profile
→ apply platform and machine-local values
```

## New-machine checklist

- Confirm the expected profile is selected.
- Apply the matching platform settings.
- Recreate machine-local executable paths.
- Sign into only the required extensions.
- Validate terminal, formatter, language server, Git, and workspace behavior.

## Profile export backups

Export stable profiles as `.code-profile`, inspect them, and store them privately.

## Temporary family or friend machines

Before leaving:

- sign out of GitHub
- sign out of AI tools
- disconnect remote systems
- remove database connections
- sign out of extension accounts
- disable Settings Sync
- uninstall VS Code when appropriate
