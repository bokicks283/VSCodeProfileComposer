# Private live-profile exports

Composer-generated `.code-profile` files do not belong here. Generate them under ignored `build/profiles/<id>/` with `-ExportCodeProfile`.

This directory is reserved for deliberately retained exports created from live VS Code profiles. A live export may contain runtime-owned resources, personal paths, machine values, account-related state, or other data not represented by the composer.

Before retaining a live export:

1. Export the stable profile from VS Code to a local file.
2. Review the complete file for personal paths, credentials, tokens, private connection data, account state, UI state, and machine-only values.
3. Store sensitive backups outside this public repository.

`.code-profile` files in this directory are ignored by default. Never use a live export as the canonical source for components or recipes, and never commit one without an explicit content review.

See [Complete usage guide](../docs/USAGE.md) for normal composition and import steps.
