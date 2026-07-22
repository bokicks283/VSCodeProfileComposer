# Global settings

`settings.jsonc` is the canonical source for settings intentionally applied to every VS Code profile through `workbench.settings.applyToAllProfiles`.

The composer generates `build/global/settings.json` for review and manual application to VS Code's built-in Default profile. These settings are deliberately absent from generated named-profile settings because VS Code ignores those copies.

Do not put machine paths, secrets, workspace policy, or profile-specific settings here.

The portable `settingsSync.ignoredSettings` value keeps the machine-specific Todo Tree ripgrep path out of Sync. The composer does not otherwise control Settings Sync.

cSpell uses custom decorations so spelling issues stay out of VS Code's Problems panel. Its correction menu is displayed inline, while the shared Default keybindings provide `Ctrl+Alt+S` for direct spelling suggestions.
