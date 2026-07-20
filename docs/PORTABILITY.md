# Portability

## Portable settings

Portable components contain editor preferences, language behavior, extension behavior, and executable names that can be resolved through `PATH`.

Suggested Baseline owns portable shell-language associations and general terminal behavior so Default works consistently across mixed repositories and machines. It does not choose the OS-specific default shell.

Portable files must not contain usernames, home paths, drive-specific SDK paths, credentials, tokens, database secrets, PowerShell remoting endpoints, module paths, or unsafe device tuning.

## Platform settings

`platform/windows.jsonc` and `platform/linux.jsonc` hold reusable OS-specific preferences.

- Windows prefers PowerShell 7 through portable `pwsh.exe` discovery.
- Linux defaults to Bash and exposes PowerShell only as an optional terminal profile.

These terminal defaults must not be duplicated in Suggested Baseline, Default, or PowerShell Development.

## Machine-local settings

Real machine values live under ignored `machine/local/`. Committed examples use placeholders only.

PowerShell executable overrides, module locations, signing certificates, remoting endpoints, and shell-specific environment adjustments are machine-local when they cannot be expressed portably.

## Workspace settings

Project behavior belongs in `.vscode/settings.json`, `.code-workspace`, or a reviewed example. Unreal generated folders and file watchers are workspace concerns, not C++ defaults.

Shell repositories also own PSScriptAnalyzer rules, Pester configuration, module paths, test tasks, publishing commands, and team formatting policy.

## Secrets policy

Never commit:

- access tokens or API keys
- passwords or connection strings
- private hosts, database profiles, SSH material, or remoting endpoints
- signing certificates or private keys
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

Default already includes everyday PowerShell, Bash/Zsh shell-script, and Windows batch support through Suggested Baseline. A user moving between Windows, Linux, family machines, and mixed repositories should not need a separate profile merely to edit normal scripts.

## New-machine checklist

- Confirm the expected profile is selected.
- Apply the matching platform settings.
- Confirm Windows opens PowerShell 7 or Linux opens Bash.
- Recreate machine-local executable and module paths.
- Sign into only the required extensions.
- Validate terminal, shell-language support, formatter, language server, Git, and workspace behavior.

## Profile export backups

Export stable profiles as `.code-profile`, inspect them, and store them privately.

## Temporary family or friend machines

Before leaving:

- sign out of GitHub
- sign out of AI tools
- disconnect remote systems and PowerShell sessions
- remove database connections
- sign out of extension accounts
- disable Settings Sync
- uninstall VS Code when appropriate
