# Main profile ownership audit — 2026-07-22

This was a read-only comparison of the live stable VS Code `Main` profile and
the repository. No VS Code file, profile, extension, UI state, account state,
or Settings Sync setting was modified.

> Snapshot note: the numeric findings below describe the live comparison at
> audit time. Later target-branch commits added reviewed global cSpell settings,
> `terminal.integrated.persistentSessionScrollback`, and
> `window.newWindowProfile`. The integrated repository validator is the current
> authority for final ownership and requires every global value to appear
> exactly once in `workbench.settings.applyToAllProfiles`.

## Sources inspected

- Built-in Default/application settings: `%APPDATA%\Code\User\settings.json`
- Stable profile metadata: `%APPDATA%\Code\User\globalStorage\storage.json`
- `Main` named-profile settings, resolved from metadata to
  `%APPDATA%\Code\User\profiles\3513eb7f\settings.json`
- Repository application, component, profile-override, and platform settings

Only setting names and comparisons needed for ownership classification were
reported. Personal paths, credentials, account data, machine values, and
opaque UI state were not copied or recorded.

## Application-owned findings

The live `workbench.settings.applyToAllProfiles` list contained 46 setting
IDs. Of those:

- 45 portable/general values are present with exact values in
  `global/settings.jsonc`;
- none of the 46 IDs is declared in a component, profile override, or platform
  overlay;
- `todo-tree.ripgrep.ripgrep` is the sole tracked-source exception because its
  live value is a personal machine path.

The Todo Tree key remains explicitly protected by
`settingsSync.ignoredSettings` in `global/settings.jsonc`. Its value belongs in
an ignored `machine/local/<id>.jsonc` overlay and is delivered only through the
generated built-in Default/application artifact. It was not copied during this
audit. This exception preserves the repository rule that machine paths never
enter portable or tracked sources.

## Main-profile findings

`Main` contained 54 settings:

- 52 already matched their repository-owned value exactly (50 in the shared
  component and 2 in the Windows platform overlay);
- `cSpell.autocorrect` was an unowned, portable, clearly cross-profile general
  preference. The shared component already owns the Code Spell Checker
  extension, so this audit added the setting to
  `components/default/settings.jsonc`;
- `todo-tree.ripgrep.ripgrep` is the machine-path exception described above.

No other unowned setting was moved. There were no ambiguous unowned values
requiring a guess about component, profile, platform, or machine ownership.

## Follow-up

On each computer, keep the Todo Tree executable value in that computer's
ignored machine overlay and run a `ProfileComposer.ps1` validating or composing
subcommand with `-Machine <id>`.
Do not add the executable path to `global/settings.jsonc` or a named-profile
source.
