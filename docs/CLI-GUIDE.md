# Complete composer CLI guide

This is the canonical operator reference for `scripts/ProfileComposer.ps1`.
It covers every command, subcommand, option, output, and safety boundary in the
current CLI. Use [Complete usage guide](USAGE.md) for the longer first-run and
maintenance tutorial.

## Invocation and help

```powershell
pwsh ./scripts/ProfileComposer.ps1 <command> [arguments] [options]
```

If the forwarding function in [Complete usage guide](USAGE.md#requirements) is
installed, `vscomp` is shorthand for the same entry point. The function must
forward `@args` unchanged so quoted paths and options remain intact.

Preferred help forms put the command first:

```powershell
pwsh ./scripts/ProfileComposer.ps1 help
pwsh ./scripts/ProfileComposer.ps1 compose help
pwsh ./scripts/ProfileComposer.ps1 compose -Help
pwsh ./scripts/ProfileComposer.ps1 route add-setting -Help
```

`-h`, `--help`, and legacy `help <command> [subcommand]` also work. Options are
case-insensitive and can appear before or after positional arguments. Quote
paths, profile names, and reasons containing spaces.

### Exit behavior

- Exit `0` means success. With `-DryRun`, the complete plan validated but was
  not applied, except when sync is explicitly given
  `-PersistDryRunDecisions` to save interactive routing choices.
- Exit `1` means input, routing, ownership, validation, or an external read/open
  operation failed.
- `validate -Strict` also fails on warnings. `route audit` fails on errors but
  reports warnings without failing.

Validation output lists every error, warning, and informational notice, with
diagnostic codes and sources when available.

## State and safety model

| State | Location | CLI behavior |
|---|---|---|
| Portable sources | `components/`, `profiles/`, `platform/`, `global/`, `config/` | Canonical repository input; changed only by explicit mutation commands |
| Private machine sources | ignored `machine/local/` | Read when selected; `sync`, `capture-ui-state`, and some renames can update it |
| Generated deliverables | `build/global/settings.json`, `build/profiles/<id>/*.code-profile` | Recreated by composition; never canonical input |
| Live VS Code | VS Code User/Profile storage | Read only where stated; never directly imported, replaced, deleted, or Sync-modified |

The forward workflow is repository sources -> validate -> compose -> review ->
manual VS Code import. The reverse workflow is private export -> `sync -DryRun`
-> review -> `sync` -> inspect the Git diff.

Named-profile merge order is: recipe components, recipe operations, platform,
schema 2 machine component scopes, then the exact machine profile scope. Later
layers win. Application settings are separate: `global/settings.jsonc`, then
the selected machine's `settings.application`.

Objects merge recursively; scalars, arrays, and `null` replace earlier values.
Extensions deduplicate case-insensitively in first-appearance order. Keybinding
arrays concatenate unchanged.

## Common options

Only commands that list an option accept it.

| Option | Meaning |
|---|---|
| `-RepositoryRoot <path>` | Advanced/test override for the composer checkout |
| `-Platform <id>` | Select a committed platform overlay |
| `-Machine <id>` | Select ignored `machine/local/<id>.jsonc` |
| `-MachineFile <path>` | Explicit machine-file escape hatch; mutually exclusive with `-Machine` |
| `-DryRun` | Validate and print the complete plan without normal target writes |
| `-Strict` | Treat repository warnings as failures |
| `-NoUiState` | Omit UI state even when an automatic seed exists |
| `-UiStateProfile <id>` | Select a stored private UI-state seed |
| `-UiStateFromProfile <path>` | Use one private export as an unstored UI-state source |
| `-VSCodeUserDataPath <path>` | Read a nonstandard stable/Insiders User directory |
| `-CodeCommand <command>` | Use another executable such as `code-insiders` |

The three UI-state choices are mutually exclusive.

## Read and validation commands

### `help`

```powershell
vscomp help
vscomp <command> -Help
vscomp route <action> -Help
```

Prints general or command-specific help. It performs no writes.

### `validate`

```powershell
vscomp validate [-Platform <id>] `
  [-Machine <id> | -MachineFile <path>] `
  [-Strict] [-RepositoryRoot <path>]
```

Validates composer configuration, the shared-default invariant, recipes,
components, global settings, overlays, extension IDs, ownership, portable-path
and privacy rules, machine schema, and selected platform/machine compatibility.
It neither composes nor changes files.

### `list-profiles` / `list profiles`

```powershell
vscomp list-profiles [-RepositoryRoot <path>]
vscomp list profiles [-RepositoryRoot <path>]
```

Lists recipe ID, display name, and ordered components. Repository commands take
the recipe ID, not the display name.

### `list-machines` / `list machines`

```powershell
vscomp list-machines [-RepositoryRoot <path>]
vscomp list machines [-RepositoryRoot <path>]
```

Lists ignored machine definitions with ID, name, platform, and schema version.
Private setting values are not printed.

## Composition commands

### `compose <profile>`

```powershell
vscomp compose <profile-id> `
  [-Platform <id>] `
  [-Machine <id> | -MachineFile <path>] `
  [-NoUiState | -UiStateProfile <id> | -UiStateFromProfile <path>] `
  [-DryRun] [-Strict] [-RepositoryRoot <path>]
```

Preflight-validates the repository, generates built-in Default settings at
`build/global/settings.json`, and creates one finished importable profile at
`build/profiles/<id>/<safe-display-name>.code-profile`.

With no explicit UI option, the target profile's stored seed is copied when
present. Otherwise, the seed named by `composer.jsonc.defaultUiStateProfile` is
the fallback. The selected seed is treated as one opaque `globalState` resource
and is never parsed or merged.

For schema 2 machines, `settings.application` goes only to the application
artifact. Matching component and profile scopes enter the named-profile export,
which is labeled machine-scoped.

### `compose-all`

```powershell
vscomp compose-all [-Platform <id>] `
  [-Machine <id> | -MachineFile <path>] `
  [-NoUiState | -UiStateProfile <id> | -UiStateFromProfile <path>] `
  [-DryRun] [-Strict] [-RepositoryRoot <path>]
```

Uses the same rules as `compose` for every recipe. A machine component scope is
applied to each recipe containing that component; a machine profile scope is
applied only to its exact recipe.

### `compose-global`

```powershell
vscomp compose-global [-Machine <id> | -MachineFile <path>] `
  [-DryRun] [-Strict] [-RepositoryRoot <path>]
```

Generates only `build/global/settings.json`. Under schema 2, only
`settings.application` participates. The output contains normalized
`workbench.settings.applyToAllProfiles` and Settings Sync ignore metadata for
machine keys. It must be manually merged into VS Code Application Settings.

## UI-state capture

### `capture-ui-state`

```powershell
# Explicit recipe
vscomp capture-ui-state <profile-id> <private-export> `
  [-DryRun] [-RepositoryRoot <path>]

# Infer recipe from exactly one active VS Code profile
vscomp capture-ui-state <private-export> `
  [-CodeCommand <command>] [-DryRun] [-RepositoryRoot <path>]
```

Stores only a validated export's opaque `globalState` at ignored
`machine/local/ui-state/<profile>/seed.code-profile`. Settings, extensions,
keybindings, name, and source path are not retained. Automatic selection reads
`code --status` and requires exactly one active name matching a recipe ID or
display name. Capturing does not update an already imported live profile.

## Synchronizing a reviewed export

### `sync`

```powershell
vscomp sync [<profile-id>] <private-export> `
  [-Platform <id>] `
  [-Machine <id> | -MachineFile <path>] `
  [-RoutingFile <path>] `
  [-RoutingMode Supplement|Override|Isolated] `
  [-NonInteractive] [-WriteUnresolved <path>] `
  [-SkipGlobal] [-SkipUiState] [-PersistDryRunDecisions] `
  [-VSCodeUserDataPath <path>] [-DryRun] `
  [-RepositoryRoot <path>]
```

`sync` is the reviewed reverse path. It imports settings, extensions,
keybindings, and optional UI state; resolves authoritative owners; validates one
complete staged repository; then applies a rollback-safe transaction. It does
not flatten everything into one profile file.

Omit the recipe only when the export name matches exactly one recipe ID or
display name. Snippet and task resources are rejected because the schema does
not own them. Sensitive values are excluded before writes and are never printed
in full.

Unless `-SkipGlobal` is used, sync also reads the selected VS Code User
directory's `settings.json`. It normalizes every top-level application setting
into the in-memory apply-to-all list, routes portable values to
`global/settings.jsonc`, routes Sync-ignored or machine-local values to
`settings.application`, and excludes sensitive values. A leading `-` in
`settingsSync.ignoredSettings` means VS Code force-syncs that setting; it does
not establish machine ownership.

Ownership resolution prefers:

1. security or machine-local classification;
2. an explicit choice made during this run;
3. custom exact routing according to `-RoutingMode`;
4. existing exact repository ownership;
5. managed exact routing;
6. approved custom/managed prefix or publisher rules;
7. grouped interactive resolution;
8. unresolved failure.

Sensitive classification always forces exclusion. Machine-local paths cannot
be routed to portable files. When such a setting has a component/profile
fallback, schema 2 can preserve it while adding a machine-component/profile
overlay. New machine-local profile settings default to the current profile
scope when a schema 2 machine is selected. For non-path values that must vary by
computer, define the scope explicitly because the value alone may look portable:

```powershell
vscomp route add-setting "tool.compilerMode" -MachineComponent cpp
vscomp route add-setting "unreal.localIndexMode" -MachineProfile unreal
```

Machine target selection order is explicit `-Machine`/`-MachineFile`, ignored
`machine/local/.default-machine`, one unique platform-compatible local machine,
then a safe failure. Scoped machine destinations require schema 2; schemas 0/1
remain application-only.

Routing modes:

| Mode | Behavior |
|---|---|
| `Supplement` | Managed router is active; custom routes add candidates (default) |
| `Override` | A matching custom route suppresses matching managed rules |
| `Isolated` | Managed router is disabled; custom rules handle non-existing matches |

Exact existing owners and classification stay active in every mode.
`-RoutingFile` is temporary and never imports routes; use `route import` for
that. `-NonInteractive` forbids prompts and fails without writes if unresolved
items remain. `-WriteUnresolved` emits a provisional router for review.
Interactive dry-run choices persist only with `-PersistDryRunDecisions`.

`-SkipUiState` permits an export without UI state. `-SkipGlobal` avoids reading
Application Settings. Missing export resources do not delete shared settings or
extensions.

When UI state is included, `sync` stores the opaque seed for the target recipe.
It does not regenerate a `.code-profile` under `build/` and does not modify any
live VS Code profile. The command reports the seed path and both unchanged
delivery boundaries. Run `vscomp compose <profile>` with the required platform
and machine options, review the generated artifact, and then import or replace
the live profile to deliver the captured UI state.

Recommended flow:

```powershell
vscomp sync ".\Adjusted Unreal.code-profile" -Platform windows `
  -Machine excalibur117-w -DryRun
vscomp sync ".\Adjusted Unreal.code-profile" -Platform windows `
  -Machine excalibur117-w
git diff --check
vscomp validate -Platform windows -Machine excalibur117-w -Strict
```

## Ownership router commands

Managed routes live in `config/ownership-router.jsonc`. Mutating route commands
use staged validation. [Ownership router and sync](OWNERSHIP-ROUTER.md) explains
the schema and precedence internals.

### Typed destinations

Every `route add-*` command takes exactly one destination:

| Option | Destination and use |
|---|---|
| `-Component <name>` | Portable component setting/extension |
| `-Platform <name>` | Portable platform setting/extension |
| `-Machine` | Machine application setting |
| `-MachineComponent <name>` | Schema 2 machine component setting |
| `-MachineProfile <name>` | Schema 2 machine profile setting |
| `-Profile <name>` | Portable exact-profile operation |
| `-Exclude` | Never store through sync |
| `-Unresolved` | Require later review |

Machine destinations cannot own extensions in the current artifact model.

### `route list`

```powershell
vscomp route list [-RepositoryRoot <path>]
```

Lists every route, kind, match, destination, status, source, and reason.

### `route show`

```powershell
vscomp route show <route-id-or-exact-item> [-RepositoryRoot <path>]
```

Prints JSON metadata for a matching ID or exact-match item.

### `route explain`

```powershell
vscomp route explain <item> [-Kind setting|extension] `
  [-Platform <id>] [-RoutingFile <path>] `
  [-RoutingMode Supplement|Override|Isolated] `
  [-RepositoryRoot <path>]
```

Prints candidates in precedence order, winner, destination file,
classification, and final validation.

### `route audit`

```powershell
vscomp route audit [-Platform <id>] [-RoutingFile <path>] `
  [-RepositoryRoot <path>]
```

Checks schema, IDs, references, duplicates, conflicts, pattern overlap,
approval state, owner disagreement, and unsafe destinations. It does not write.

### `route add-setting` / `route add-extension`

```powershell
vscomp route add-setting <key> <typed-destination> `
  [-Id <id>] [-Reason <text>] [-Source <value>] `
  [-Status approved|provisional|disabled] [-DryRun] `
  [-RepositoryRoot <path>]

vscomp route add-extension <publisher.id> <typed-destination> `
  [-Id <id>] [-Reason <text>] [-Source <value>] `
  [-Status approved|provisional|disabled] [-DryRun] `
  [-RepositoryRoot <path>]
```

Adds an exact route. Defaults are a generated ID, source `user-confirmed`,
status `approved`, and reason `Added through vscomp route.` Approved routes
apply automatically; provisional routes are suggestions; disabled routes do
not participate.

### `route add-prefix`

```powershell
vscomp route add-prefix <prefix> <typed-destination> -ConfirmBroadRule `
  [-Kind setting|extension] [-Id <id>] [-Reason <text>] `
  [-Source <value>] [-Status approved|provisional|disabled] `
  [-DryRun] [-RepositoryRoot <path>]
```

Adds a broad prefix route. Kind defaults to `setting`. The confirmation switch
is mandatory because future items can match it; audit afterward for overlaps.

### `route add-publisher`

```powershell
vscomp route add-publisher <publisher> <typed-destination> `
  -ConfirmBroadRule [-Id <id>] [-Reason <text>] [-Source <value>] `
  [-Status approved|provisional|disabled] [-DryRun] `
  [-RepositoryRoot <path>]
```

Adds a broad extension-publisher route. Confirmation is mandatory.

### `route enable` / `route disable` / `route remove`

```powershell
vscomp route enable <route-id> [-DryRun] [-RepositoryRoot <path>]
vscomp route disable <route-id> [-DryRun] [-RepositoryRoot <path>]
vscomp route remove <route-id> [-DryRun] [-RepositoryRoot <path>]
```

Enable sets `approved`, disable sets `disabled`, and remove deletes the route.
All address the route by ID and validate before applying.

### `route import`

```powershell
vscomp route import <custom-router> [-DryRun] [-RepositoryRoot <path>]
```

Imports validated non-conflicting routes into the managed router with
`custom-file` provenance. This differs from temporary `sync -RoutingFile`.

## Repository maintenance commands

### `fix global`

```powershell
vscomp fix global [-DryRun] [-RepositoryRoot <path>]
```

Creates a missing `workbench.settings.applyToAllProfiles`, removes duplicate
entries while keeping the first, and appends existing global values missing
from the list. It refuses missing values, invalid entries, and cross-layer
conflicts rather than guessing.

### `rename-profile` / `rename profile`

```powershell
vscomp rename-profile <old-id> <new-id> [-DryRun] [-RepositoryRoot <path>]
vscomp rename profile <old-id> <new-id> [-DryRun] [-RepositoryRoot <path>]
```

Renames the recipe and related repository profile sources, including an
optional local UI-state seed. It never renames a live VS Code profile.

### `rename-component` / `rename component`

```powershell
vscomp rename-component <old-id> <new-id> [-DryRun] [-RepositoryRoot <path>]
vscomp rename component <old-id> <new-id> [-DryRun] [-RepositoryRoot <path>]
```

Renames the component, recipe references, and configured defaults when needed.

### `default show` / `default set`

```powershell
vscomp default show [-RepositoryRoot <path>]
vscomp default set <component> [-DryRun] [-RepositoryRoot <path>]
```

Show prints `sharedDefaultComponent`. Set changes it and normalizes every recipe
so the component appears exactly once and first. It does not change the separate
`defaultUiStateProfile` setting.

### `migrate legacy-sync`

```powershell
# Audit only
vscomp migrate legacy-sync [-RepositoryRoot <path>]

# Preview/apply archival
vscomp migrate legacy-sync -ConfirmArchive [-BackupName <id>] `
  [-DryRun] [-RepositoryRoot <path>]
```

Audits sidecars from the pre-router sync workflow. With confirmation, it copies
candidates to `migration-backups/<BackupName>/` before removing them from
`profiles/`; the default name is `legacy-sync-manual`. Non-identical existing
backups fail safely. Archival can change profile behavior, so inspect the list
and Git diff.

## Guided VS Code commands

Only `vscode open` launches VS Code. None of these commands directly imports,
replaces, deletes, or changes Settings Sync.

### `vscode list`

```powershell
vscomp vscode list [-VSCodeUserDataPath <path>]
```

Lists live display names and opaque location IDs without reading settings.

### `vscode open`

```powershell
vscomp vscode open <live-profile> [workspace] `
  [-CodeCommand <command>] [-VSCodeUserDataPath <path>] [-DryRun]
```

Verifies one exact live profile and optional existing workspace, then invokes
`code --new-window --profile <name> [workspace]`. Dry-run prints the command.
Duplicate names are rejected.

### `vscode import`

```powershell
vscomp vscode import <recipe-id> [-Platform <id>] `
  [-Machine <id> | -MachineFile <path>] `
  [-NoUiState | -UiStateProfile <id> | -UiStateFromProfile <path>] `
  [-Strict] [-DryRun] [-RepositoryRoot <path>] `
  [-VSCodeUserDataPath <path>]
```

Composes the artifact and prints its path plus manual Import Profile steps. It
does not perform the import. `-VSCodeUserDataPath` is accepted for isolated
workflows, although import has no live target.

### `vscode replace`

```powershell
vscomp vscode replace <recipe-id> -LiveProfile <existing-name> `
  [-Platform <id>] [-Machine <id> | -MachineFile <path>] `
  [-NoUiState | -UiStateProfile <id> | -UiStateFromProfile <path>] `
  [-Strict] [-DryRun] [-RepositoryRoot <path>] `
  [-VSCodeUserDataPath <path>]
```

Verifies the live target, refuses built-in Default, composes a replacement, and
prints backup/import/verify/delete steps. It does not replace the target.

### `vscode delete`

```powershell
vscomp vscode delete <live-profile> [-VSCodeUserDataPath <path>] [-DryRun]
```

Verifies the exact target, refuses built-in Default, and prints the supported
Profiles: Delete Profile action. It never deletes the profile itself.

## Machine schema 2 and CLI routing

```jsonc
{
  "schemaVersion": 2,
  "machine": {
    "id": "main-windows",
    "name": "Main Windows workstation",
    "platform": "windows",
    "hostnames": ["MAIN-PC"]
  },
  "settings": {
    "application": {
      "todo-tree.ripgrep.ripgrep": "C:\\Tools\\rg.exe"
    },
    "components": {
      "cpp": {
        "C_Cpp.default.compilerPath": "C:\\Toolchains\\clang-cl.exe"
      }
    },
    "profiles": {
      "unreal": {
        "unreal.localIndexMode": "reduced"
      }
    }
  }
}
```

The container determines ownership: application is built-in Default,
components are reusable machine-local component overlays, and profiles are
exact machine-local profile overlays. Every selected machine key enters
generated `settingsSync.ignoredSettings`; only application keys also enter
`workbench.settings.applyToAllProfiles`. See [Schema and ownership
contract](SCHEMA.md) and [Machine-local configuration](../machine/README.md).

## Mutation matrix

| Command | Repository source | Private machine source | `build/` | Live VS Code read/open | Live profile/Sync write |
|---|---:|---:|---:|---:|---:|
| `help`, `validate`, `list-*`, route reads | No | No | No | No | No |
| `compose*` | No | Read | Yes unless dry-run | No | No |
| `capture-ui-state` | No | Yes unless dry-run | No | Status read only when inferring | No |
| `sync` | Yes unless dry-run; routing choices may persist with the explicit persistence switch | Yes unless dry-run | No | Application settings unless skipped | No |
| Route mutations, `fix`, `rename-*`, `default set`, confirmed `migrate` | Yes unless dry-run | Rename may move a UI seed | No | No | No |
| `vscode import`/`replace` | No | Read | Yes unless dry-run | Replace reads metadata | No |
| `vscode list`/`delete` | No | No | No | Metadata read | No |
| `vscode open` | No | No | No | Metadata read; opens unless dry-run | No |

## Compatibility wrappers and checklist

`scripts/Compose-Profile.ps1` and `scripts/Save-ProfileUiState.ps1` remain for
older automation but expose only historical subsets. Use
`scripts/ProfileComposer.ps1` for all new work.

For normal delivery:

```powershell
vscomp validate -Platform windows -Machine excalibur117-w -Strict
vscomp compose cpp -Platform windows -Machine excalibur117-w -DryRun
vscomp compose cpp -Platform windows -Machine excalibur117-w
pwsh -NoProfile -NonInteractive -File ./scripts/Test-Documentation.ps1
pwsh -NoProfile -Command "Invoke-Pester -Path ./tests -Output Detailed -CI"
git diff --check
```

Preview every mutation that supports `-DryRun`, review its target list, apply,
inspect `git diff`, then validate and compose. Keep private exports and all
`machine/local/` content out of Git.
