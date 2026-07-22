# Historical extension reference

This directory preserves a sanitized extension-ID inventory from the live VS Code profile export named `Extension Library Staging`, exported on 2026-07-21.

The source export contained settings, extensions, and `globalState`. Only the extension identifiers were extracted. The original `.code-profile`, settings, UI state, display metadata, and other live profile data are not committed.

## Snapshot

- 150 unique extension IDs
- 150 valid Marketplace-style IDs
- 0 duplicate IDs
- 50 IDs currently owned by repository components
- 100 historical-only candidates
- 0 active repository IDs missing from the snapshot

The inventory is [extension-library-staging.txt](extension-library-staging.txt).

The current repository and live `Main` comparison is documented in [2026-07-21-main-gap-review.md](2026-07-21-main-gap-review.md).

This is historical project memory, not an install list or component. The composer never reads it during validation or composition. It includes extensions that were intentionally retired or deferred, including `trunk.io`, so do not add the file wholesale to a profile.

After the composed profiles have been used in representative workspaces, compare missing capabilities against this inventory. Add only extensions with a current, profile-specific reason to the smallest correct component. The component `extensions.txt` files remain canonical.
