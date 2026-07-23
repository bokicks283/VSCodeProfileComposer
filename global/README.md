# Global settings

`settings.jsonc` is the canonical source for settings intentionally applied to every VS Code profile through `workbench.settings.applyToAllProfiles`.

If validation reports duplicate IDs or values missing from that ownership array, preview `pwsh ./scripts/ProfileComposer.ps1 fix global -DryRun`, then apply `fix global` after reviewing the plan. The command preserves first-occurrence order, appends unlisted values, validates in staging, and rolls back on failure. It does not guess missing values or cross-layer ownership. A changed file is rewritten as normalized JSON, so review the Git diff for comment removal.

Run `pwsh ./scripts/ProfileComposer.ps1 compose-global` to generate `build/global/settings.json` for review and manual application to VS Code's built-in Default profile. These settings are deliberately absent from generated named-profile settings because VS Code ignores those copies.

After changing an application-owned value in VS Code, a reviewed `ProfileComposer.ps1 sync <export>` transaction reads the built-in Default `settings.json` and refreshes only keys explicitly listed by its live `workbench.settings.applyToAllProfiles`. Keys ignored by Settings Sync are treated as machine-owned and their values are excluded. Preview with `-DryRun` and inspect the Git diff.

Do not put machine paths, secrets, workspace policy, or profile-specific settings here.

The portable `settingsSync.ignoredSettings` value keeps the machine-specific Todo Tree ripgrep path out of Sync. The composer does not otherwise control Settings Sync.

cSpell uses custom decorations so spelling issues stay out of VS Code's Problems panel. Its correction menu is displayed inline, while the shared Default keybindings provide `Ctrl+Shift+S` for direct spelling suggestions.

`terminal.integrated.persistentSessionScrollback` and `window.newWindowProfile` are also application-owned. Their values are listed exactly once in `workbench.settings.applyToAllProfiles` and must not be duplicated in components.
