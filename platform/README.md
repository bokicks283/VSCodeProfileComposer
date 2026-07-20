# Platform settings

These files contain reusable OS-specific preferences without usernames, personal home paths, SDK roots, credentials, or device tuning.

- `windows.jsonc` prefers PowerShell 7 through `pwsh.exe`.
- `linux.jsonc` keeps Bash as the default and exposes PowerShell as optional.

Pass the matching ID to the composer with `-Platform windows` or `-Platform linux`. Machine-specific values apply afterward and belong under ignored `machine/local/`.
