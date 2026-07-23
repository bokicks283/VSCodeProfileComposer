# Legacy sync backup

These files preserve the profile-local sidecars created by the pre-router
`sync` implementation on 2026-07-23. They are evidence only and are never
composed.

The sidecars were removed from `profiles/` during the managed-router migration:

- the MSSQL keybinding already has the exact authoritative owner
  `components/sql-server/keybindings.jsonc`;
- the cSpell removal was inferred from absence in one flattened export, which
  the new conservative removal policy forbids;
- `workbench.editorAssociations` was unowned and had been sent to the profile
  fallback without an explicit routing decision.

Review and route the editor association explicitly before reintroducing it.
