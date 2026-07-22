# Portability

## Portable settings

Portable components contain editor preferences, language behavior, extension behavior, and executable names that can be resolved through `PATH`.

Default owns portable shell-language associations and general terminal behavior so every profile works consistently across mixed repositories and machines. It does not choose the OS-specific default shell.

Database components may contain safe behavior settings and extension IDs, but never live connection or authentication data.

Portable files must not contain usernames, home paths, drive-specific SDK paths, credentials, tokens, database secrets, PowerShell remoting endpoints, module paths, or unsafe device tuning.

## Platform settings

`platform/windows.jsonc` and `platform/linux.jsonc` hold reusable OS-specific preferences.

- Windows prefers PowerShell 7 through portable `pwsh.exe` discovery.
- Linux defaults to Bash and exposes PowerShell only as an optional terminal profile.

These terminal defaults must not be duplicated in Default or PowerShell Development.

Database command-line clients, native drivers, and certificate behavior may vary by platform, but connection data still remains outside committed platform files.

## Machine-local settings

Real machine values live under ignored `machine/local/`. Committed examples use placeholders only.

PowerShell executable overrides, module locations, signing certificates, remoting endpoints, database client paths, SSH tunnels, and shell-specific environment adjustments are machine-local when they cannot be expressed portably.

Database extensions may retain saved connections or authentication state outside this repository. That state must not be copied into portable component files.

## Workspace settings

Project behavior belongs in `.vscode/settings.json`, `.code-workspace`, or a reviewed example. Unreal generated folders and file watchers are workspace concerns, not C++ defaults.

Shell repositories own PSScriptAnalyzer rules, Pester configuration, module paths, test tasks, publishing commands, and team formatting policy.

Database repositories own schema projects, migrations, environment selection, query conventions, test data policy, and team connection rules. Employer-specific database tooling belongs in employer-managed configuration or a local work profile, not personal Default.

## Secrets policy

Never commit:

- access tokens or API keys
- passwords or connection strings
- database hosts, ports, usernames, private database names, or saved connection objects
- private cloud resources, account IDs, certificates, or authentication caches
- private hosts, database profiles, SSH material, or remoting endpoints
- signing certificates or private keys
- extension account state
- exported profile files before inspection

## Settings Sync workflow

```text
Compose a portable .code-profile without a machine overlay
→ import it into a new named VS Code profile
→ review and validate the imported resources locally
→ customize live UI placement in VS Code
→ review Settings Sync resource selection
→ enable Sync only when the profile is ready to travel
→ recreate machine-only values locally
```

Settings Sync can synchronize settings, keyboard shortcuts, snippets, tasks, UI state, extensions, and profiles. Generated exports omit UI state by default. An explicit `-UiStateFromProfile` snapshot makes the artifact private and non-portable even though VS Code owns the live UI after import.

When adding a second machine, review **Settings Sync: Configure** before enabling synchronization. If unexpected changes occur, pause further synchronization, identify the affected resource, inspect **Settings Sync: Show Synced Data**, and back up both machines before restoring or resetting anything. The composer never controls Settings Sync.

Default already includes everyday PowerShell, Bash/Zsh shell-script, and Windows batch support, and every focused recipe begins with Default. A user moving between Windows, Linux, family machines, and mixed repositories should not need a separate profile merely to edit normal scripts.

Database tooling is selected only when the active profile composes `database` or a vendor-specific database component.

## New-machine checklist

- Generate or select an export composed with the matching platform overlay.
- Import it into a new named profile and review the selected resources.
- Confirm the expected profile is selected.
- Confirm Windows opens PowerShell 7 or Linux opens Bash.
- Recreate machine-local executable and module paths.
- Sign into only the required extensions.
- Recreate database connections locally only when the selected profile needs them.
- Validate terminal, shell-language support, formatter, language server, Git, database, and workspace behavior as applicable.

## Profile export backups

Generate portable `.code-profile` artifacts under ignored `build/profiles/` with `-ExportCodeProfile`. Inspect them before import or private storage. A composer-generated database profile contains only repository-owned settings and extension identifiers, but still review it before use.

Separately, a profile exported from live VS Code can contain additional runtime-owned resources or machine/account state. Treat live exports as sensitive until inspected and store them privately rather than using them as canonical repository source. When one is passed through `-UiStateFromProfile`, only its opaque `globalState` resource is copied, but that resource can itself contain extension or account-related state. It is a one-time layout seed, not a portable or canonical source.

## Temporary family or friend machines

Before leaving:

- sign out of GitHub
- sign out of AI tools
- disconnect remote systems and PowerShell sessions
- remove database connections and sign out of database extensions
- sign out of extension accounts
- disable Settings Sync
- uninstall VS Code when appropriate
