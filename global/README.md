# Global settings

`settings.jsonc` is the canonical source for settings intentionally applied to every VS Code profile through `workbench.settings.applyToAllProfiles`.

The composer generates `build/global/settings.json` for review and manual application to VS Code's built-in Default profile. These settings are deliberately absent from generated named-profile settings because VS Code ignores those copies.

Do not put machine paths, secrets, workspace policy, or profile-specific settings here.
