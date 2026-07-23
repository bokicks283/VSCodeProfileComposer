# Ownership router and repository synchronization

## Purpose

`vscomp sync` is a repository synchronization command. It imports a reviewed
`.code-profile`, resolves one authoritative owner for every imported setting
and extension, validates the entire routed mutation plan, and then updates the
owning files in one rollback-safe transaction.

Unknown portable items are never dumped into `profiles/`. Profile-local
ownership is an explicit route, not a fallback.

## Canonical ownership layers

| Destination | Meaning | Setting file | Extension file |
| --- | --- | --- | --- |
| `component/<name>` | Reusable portable behavior | `components/<name>/settings.jsonc` | `components/<name>/extensions.txt` |
| `platform/<name>` | Reusable OS behavior | `platform/<name>.jsonc` | `platform/<name>.extensions.txt` |
| `machine` | Selected computer | `machine/local/<id>.jsonc` | Not composable; reject and choose another destination |
| `profile/<name>` | Explicit rare profile-only behavior | `profiles/<name>.settings.replace.jsonc` | `profiles/<name>.extensions.jsonc` |
| `exclude` | Sensitive, volatile, or intentionally ignored data | No file | No file |
| `unresolved` | Requires a decision | No file | No file |

Machine routes do not embed a personal machine ID. `-Machine <id>` resolves
the target at synchronization time.

## Managed router

The system-managed registry is:

```text
config/ownership-router.jsonc
```

Its dependency-free JSONC schema is:

```jsonc
{
  "schemaVersion": 1,
  "routes": [
    {
      "id": "python-settings",
      "kind": "setting",
      "match": {
        "type": "prefix",
        "value": "python."
      },
      "destination": {
        "type": "component",
        "name": "python"
      },
      "source": "repository-policy",
      "status": "approved",
      "reason": "Portable Python settings belong to the Python component."
    }
  ]
}
```

Route kinds:

- `setting`
- `extension`

Match types:

- `exact`
- `prefix`
- `publisher` for extension publishers

Provenance:

- `repository-policy`
- `user-confirmed`
- `custom-file`
- `inferred`
- `migration`

Approval states:

- `approved` applies automatically;
- `provisional` is a suggestion and still requires confirmation;
- `disabled` does not participate.

Broad prefix and publisher routes require explicit confirmation when added
through the CLI.

## Resolution precedence

The resolver uses this deterministic order:

1. explicit decision for this sync;
2. custom exact route;
3. unique exact repository ownership;
4. managed exact route;
5. custom approved pattern, longest match first;
6. managed approved pattern, longest match first;
7. interactive decision;
8. unresolved failure.

Exact mappings beat patterns. Existing exact ownership beats managed patterns.
Same-precedence contradictory matches fail instead of using file order.

Two classification rules remain authoritative:

- sensitive/private values force `exclude`;
- machine-local paths force `machine`.

When classification or a higher-precedence custom decision changes an existing
owner, sync moves the item instead of leaving two sources of truth.

## Sync lifecycle

```text
import and normalize export
→ discover existing ownership
→ load and validate managed/custom routes
→ classify nested values
→ collect and group unresolved items
→ resolve interactively or fail non-interactively
→ build every source mutation
→ preview
→ validate staged repository
→ commit atomically
→ validate again or roll back
```

The source export, live VS Code profiles, installed extensions, Settings Sync,
and desktop UI are never modified.

Use `-SkipGlobal` to omit built-in Default/application reconciliation and
`-SkipUiState` when the export intentionally has no UI-state resource.

## Normal interactive use

```powershell
vscomp sync ".\Main.code-profile" `
  -Platform windows `
  -Machine main-windows
```

The terminal first offers to resolve, export a starter routing file, or abort.
Unresolved items are then grouped by setting namespace or extension publisher.
For each group, apply one destination, accept a labeled suggestion, route every
item individually, or leave the group unresolved. A decision can be:

- this sync only;
- saved as exact approved routes;
- saved as an explicitly confirmed prefix/publisher rule.

Destinations use `component/<name>`, `platform/<name>`, `machine`,
`profile/<name>`, `exclude`, or `unresolved`.

Before a broad rule is saved, the preview shows its proposed match, all
currently imported matches, existing repository items that also match, and
overlapping approved route IDs. An explicit confirmation is required.

Dry-run decisions do not persist by default:

```powershell
vscomp sync ".\Main.code-profile" `
  -Platform windows `
  -Machine main-windows `
  -DryRun
```

Use `-PersistDryRunDecisions` only when the routing decisions should be saved
while all source mutations remain a preview.

## Non-interactive use

```powershell
vscomp sync ".\Main.code-profile" `
  -Platform windows `
  -Machine main-windows `
  -NonInteractive `
  -WriteUnresolved ".\unresolved-routing.yaml"
```

Non-interactive mode never prompts. Any unresolved item exits nonzero before
repository mutation. `-WriteUnresolved` creates a schema-valid provisional
router file for review.

## Custom routing files

Custom files accept `.json`, `.jsonc`, `.yaml`, or `.yml` and use the same
schema. YAML is deliberately restricted to the deterministic shape emitted by
the unresolved-file writer.

```powershell
vscomp sync ".\Main.code-profile" `
  -Platform windows `
  -Machine main-windows `
  -RoutingFile ".\temporary-routes.yaml" `
  -RoutingMode Supplement
```

Modes:

- `Supplement` (default): custom routes participate at their documented
  precedence alongside managed routes.
- `Override`: a matching custom route suppresses matching managed candidates.
- `Isolated`: the managed router is disabled. Existing exact ownership and
  security/machine classification remain active.

Using `-RoutingFile` never mutates the managed router. Import is explicit:

```powershell
vscomp route import ".\reviewed-routes.yaml" -DryRun
vscomp route import ".\reviewed-routes.yaml"
```

## Router commands

```powershell
vscomp route list
vscomp route show python-settings
vscomp route explain "python.analysis.typeCheckingMode" -Platform windows
vscomp route audit -Platform windows

vscomp route add-setting "editor.formatOnSave" `
  -Component main `
  -Reason "Shared editor baseline"

vscomp route add-extension "ms-python.python" `
  -Component python `
  -Reason "Python language support"

vscomp route add-prefix "eslint." `
  -Component web `
  -ConfirmBroadRule `
  -Reason "Reusable ESLint behavior"

vscomp route add-publisher "ms-python" `
  -Component python `
  -ConfirmBroadRule

vscomp route disable stale-route
vscomp route enable stale-route
vscomp route remove stale-route -DryRun
```

Typed setting routes include:

```powershell
vscomp route add-setting "some.setting" -Platform windows
vscomp route add-setting "some.path" -Machine
vscomp route add-setting "profile.only.setting" -Profile main
vscomp route add-setting "extension.authState" -Exclude
```

`route explain` reports every candidate, precedence, winner, destination file,
existing ownership, classification override, and final validation state.

`route audit` reports invalid schema versions and IDs, duplicate or
contradictory matches, missing destinations, approval state, broad/overlapping
patterns, routes with no current match, duplicate exact repository ownership,
owner disagreement, uncomposable extension destinations, and unsafe exact
routes. Errors exit nonzero; warnings are review items.

## Machine resolution

Machine ownership resolves in this order:

1. `-Machine` or repository-local `-MachineFile`;
2. ignored `machine/local/.default-machine`;
3. one unique platform-compatible machine definition;
4. actionable failure.

Machine-local values are recursively detected in strings, nested objects, and
arrays. Windows/POSIX absolute paths, UNC paths, home-relative paths,
home-environment paths, and file URIs are machine-local. A broad component
route cannot override that classification.

## Sensitive values

Credential-like keys/values, connection/account state, private hosts,
certificates, SSH/private-key material, tokens, and authentication state force
`exclude`. No route can force them into component, platform, profile, or
ordinary machine JSONC. Reports do not include their value.

## Removal policy

Absence from one exported profile never removes a shared setting or extension.
Exports can omit disabled extensions or resources owned by another profile,
and shared deletion could affect many recipes.

Sync only moves an item when an imported value has a concrete higher-priority
owner or classification. Legacy profile-sidecar removals are preserved until
explicitly reviewed or archived.

## Legacy migration

Audit sidecars from the old profile-fallback sync:

```powershell
vscomp migrate legacy-sync
```

Archive them only after review:

```powershell
vscomp migrate legacy-sync `
  -ConfirmArchive `
  -BackupName legacy-sync-review `
  -DryRun

vscomp migrate legacy-sync `
  -ConfirmArchive `
  -BackupName legacy-sync-review
```

The command backs up each source under `migration-backups/<name>/`, validates
the staged repository, and then removes the original from `profiles/`.
Conflicting backups fail safely. Archiving changes profile behavior; route
retained items explicitly before reintroducing them.

## Exit codes and safety

- `0`: help/list/show, successful audit without errors, valid dry-run, or
  complete applied transaction.
- `1`: invalid input/schema, missing owner, ownership/routing conflict,
  unresolved non-interactive item, unsafe destination, or failed validation.

All implementation and validation paths are terminal-only. No sync/router
command invokes VS Code, a browser, Explorer, an editor, a documentation
preview, a graphical runner, or watch mode.
