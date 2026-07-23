# Sync routing and schema-model audit — 2026-07-23

## Confirmed root cause

The old sync planner treated every imported setting not already owned by
global or platform sources as a portable recipe replacement. Recursive
repository validation then correctly rejected a personal absolute path in that
planned tracked file. Machine routing existed for forward composition but not
for reverse synchronization.

## Corrected in this change

- recursive setting classification now precedes plan construction;
- safe machine paths route to a selected ignored machine definition;
- `sync` accepts `-Machine` and `-MachineFile`;
- explicit, local-default, and unique compatible machine resolution is
  deterministic;
- existing machine values produce add, update, or retain actions by setting
  key;
- machine routing participates in the existing staged rollback transaction;
- secret/private settings fail with redacted diagnostics before staging;
- versioned machine identity metadata is supported while legacy overlays
  remain compatible;
- platform sources now receive the same portable path validation as component,
  recipe, and global sources;
- duplicate portable setting ownership is reported for review;
- repeat sync is idempotent, and preview/apply use one planner;
- forwarding-function and alias invocation is covered by tests.

## Superseded boundary and managed-router follow-up

- Workspace settings are not imported from a user-profile export because that
  export contains no workspace provenance.
- Secret and private resources are excluded, not stored in ordinary machine
  JSONC.
- Profile exports do not carry component provenance, but the repository can
  discover exact existing owners. The later managed-router implementation now
  updates those owners directly and requires an approved route or grouped
  decision for genuinely new values. Recipe-local ownership is explicit, not a
  fallback.
- Machine schema 1 supports durable ID, display name, platform, and optional
  hostname metadata. Rename/delete lifecycle commands and stale-host
  reconciliation are not implemented.
- WSL, container, macOS, and remote machine identities are representable, but
  committed platform overlays and `.code-profile` keybinding export support
  remain limited to the platforms currently implemented by their respective
  command paths.
- The format records later-layer behavior but does not yet declare an explicit
  allow-list of intentional per-setting overrides. Cross-component duplicates
  therefore warn rather than being automatically rewritten.
- JSONC comments cannot be reconstructed when sync changes a parsed source
  file. Unchanged files retain their original bytes; changed sync-managed files
  are normalized JSON.

The canonical current behavior is documented in
[Ownership router and repository synchronization](../OWNERSHIP-ROUTER.md).
