# Platform settings

These files contain reusable OS-specific preferences without usernames, personal home paths, SDK roots, credentials, or device tuning.

- `windows.jsonc` prefers PowerShell 7 through `pwsh.exe`.
- `linux.jsonc` keeps Bash as the default and exposes PowerShell as optional.

Apply the matching file manually after creating or syncing a profile. Machine-specific values override these conceptually and belong under ignored `machine/local/`.
