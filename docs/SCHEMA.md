# Schema and ownership contract

The runtime parsers and validators in `scripts/ProfileComposer.psm1` are the
authoritative schema implementation. This document records the persisted
contracts that those parsers enforce.

## Configuration layers

Settings have one effective ownership layer:

```text
portable components
→ recipe removals and overrides
→ platform settings
→ machine-local application settings
→ workspace settings outside the composer
```

`global/settings.jsonc` is a separate portable ownership stream for settings
that VS Code applies to all profiles through its built-in Default profile.
Machine values are merged into that application artifact after global values
and are removed from named-profile output.

The composer represents component membership explicitly in profile YAML.
Platform ownership is explicit by file, and machine ownership is explicit in a
selected machine definition. New imported ownership is represented by the
versioned managed router in `config/ownership-router.jsonc`; custom JSONC/YAML
files use the same schema. Workspace settings and excluded private state are
classification outcomes, not composable source layers.

VS Code setting values retain the complete JSON domain: string, number,
boolean, object, array, or null. Arrays and nested objects are inspected
recursively for path and sensitive leaves.

## Composer configuration

`composer.jsonc` uses profile/component IDs and currently contains:

```jsonc
{
  "sharedDefaultComponent": "main",
  "defaultUiStateProfile": "main"
}
```

- `sharedDefaultComponent` is required, must resolve to a component, and must
  appear exactly once and first in every recipe.
- `defaultUiStateProfile` is optional. When present, it must resolve to a
  recipe. Normal composition copies that recipe's ignored
  `machine/local/ui-state/<id>/seed.code-profile` into every generated profile.
- The ignored seed may legitimately be absent on a new checkout. Composition
  then succeeds without `globalState` and reports the unavailable seed.
- One opaque seed is copied without parsing or merging. `-UiStateProfile` and
  `-UiStateFromProfile` are explicit one-run overrides; `-NoUiState` disables
  seeding.
- Renaming the referenced profile updates `defaultUiStateProfile`
  transactionally.

## Versioned machine definition

New machine files use schema version 1:

```jsonc
{
  "schemaVersion": 1,
  "machine": {
    "id": "main-windows",
    "name": "Main Windows",
    "platform": "windows",
    "hostnames": []
  },
  "settings": {
    "todo-tree.ripgrep.ripgrep": "C:\\Users\\<username>\\bin\\rg.exe"
  }
}
```

- `machine.id` is the durable ID and must match the filename without
  `.jsonc`.
- `machine.name` is a human-readable label and may change without changing the
  ID.
- `machine.platform` accepts `windows`, `linux`, `macos`, `wsl`, `container`,
  or `remote`.
- `machine.hostnames` is optional matching metadata. Hostname is never the
  durable identity.
- `settings` is a VS Code settings object.
- Unknown schema or machine fields fail closed.
- A newer unsupported `schemaVersion` fails with a compatibility error.

Existing unwrapped machine setting maps remain readable as legacy schema 0.
Their filename is the ID and their platform is unknown. A sync that changes a
legacy file preserves the legacy shape. Copy the current committed examples to
adopt schema 1; no tracked migration is required because real machine files are
ignored.

## Machine resolution for sync

Machine-local routing resolves a target only when the imported profile
contains a routable machine value:

1. explicit `-Machine` or `-MachineFile`;
2. the ID in ignored `machine/local/.default-machine`;
3. exactly one machine compatible with the selected platform;
4. otherwise an actionable failure.

An explicit selection overrides the local default. Platform metadata must
agree with `-Platform`. A legacy machine with no platform metadata can be a
unique fallback, but it cannot disambiguate multiple machines.
For sync writes, an explicit `-MachineFile` must still resolve under
`machine/local/` so it can participate in the same rollback transaction.

Create a private default selector with:

```powershell
Set-Content ./machine/local/.default-machine 'main-windows'
```

The selector and every real machine definition are covered by
`machine/local/*` in `.gitignore`.

## Import classification

`sync` classifies imported setting values before it builds tracked recipe
changes.

- Absolute drive paths, Windows forward-slash paths, UNC paths, POSIX absolute
  paths, home-relative paths, supported home environment-variable paths, and
  `file:` paths route to the selected machine definition.
- Bare executable names such as `rg` and `pwsh` remain portable.
- Ordinary slash-bearing labels such as `publisher/extension` remain
  portable.
- Credential-like keys or values, saved connection/account resources, private
  endpoints, certificates, and SSH/private-key material are classified as
  excluded private state and fail before any source write.
- Unsupported profile resources such as tasks and snippets continue to fail
  rather than being discarded.

Diagnostics show the setting key, source export, classification, destination,
platform, machine, owner, rule ID, reason, and corrective command. Machine and
sensitive values are redacted.

## Ownership and conflicts

- Global ownership conflicting with a component, recipe, or platform is an
  error.
- Sync requires one unique exact repository owner. Multiple component,
  platform, machine, or explicit profile owners are a blocking ownership
  conflict.
- A machine/platform mismatch is an error.
- Multiple compatible automatic machine targets are ambiguous and fail.
- Explicit machine selection permits the same setting key on different
  machines; the selected machine owns the routed value.
- A machine value may intentionally override an earlier portable or platform
  value. The route report records that earlier owner.
- Repository-wide validation warns about duplicate portable component
  ownership so existing compositions remain inspectable; synchronization
  refuses to choose between those owners.

## Ownership router schema 1

The router root contains only `schemaVersion` and `routes`. Each route requires
`id`, `kind`, `match`, `destination`, `source`, `status`, and `reason`.

```jsonc
{
  "schemaVersion": 1,
  "routes": [
    {
      "id": "eslint-settings",
      "kind": "setting",
      "match": { "type": "prefix", "value": "eslint." },
      "destination": { "type": "component", "name": "web" },
      "source": "repository-policy",
      "status": "approved",
      "reason": "Portable ESLint behavior belongs to Web."
    }
  ]
}
```

Kinds are `setting` and `extension`. Match types are `exact`, `prefix`, and
extension-only `publisher`. Destination types are `component`, `platform`,
`machine`, `profile`, `exclude`, and `unresolved`. Component/platform/profile
destinations require a valid repository name; the other destinations may not
embed a name.

Provenance values are `repository-policy`, `user-confirmed`, `custom-file`,
`inferred`, and `migration`. Status values are `approved`, `provisional`, and
`disabled`.

See [Ownership router and repository synchronization](OWNERSHIP-ROUTER.md) for
precedence and custom-mode semantics.

## Preview, apply, and compatibility

Dry run and apply call the same sync planner. The planner builds owner, router,
global, machine, and UI-state changes in one staging repository, validates the
complete routed state, and then swaps only changed paths. Post-write validation
failure rolls back every swapped path. Repeating the same sync produces no
source changes.

The VS Code `.code-profile` template remains an unversioned external format
verified against the version documented by the composer. Unknown outer fields
fail closed so a newer VS Code resource cannot be silently lost.
