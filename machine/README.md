# Machine-local settings

Copy the matching example into `machine/local/`, give it a stable computer ID, and replace placeholders locally. Files under `machine/local/` are ignored. New files use schema version 1:

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

The durable `machine.id` must match the filename. The display name and optional hostnames may change without changing identity. Existing plain settings maps remain compatible as legacy schema 0.

For example:

```powershell
Copy-Item ./machine/windows.example.jsonc ./machine/local/main-windows.jsonc
Copy-Item ./machine/windows.example.jsonc ./machine/local/gaming-server.jsonc
pwsh ./scripts/ProfileComposer.ps1 list-machines
pwsh ./scripts/ProfileComposer.ps1 compose unreal -Platform windows -Machine main-windows
```

The filename without `.jsonc` is the `-Machine` ID. This makes the intended target explicit and records it in the manifest. `-MachineFile` remains an explicit-path escape hatch; do not use both switches together.

`sync` accepts the same `-Machine` syntax. When a reviewed export contains a safe absolute path, it excludes that key from portable recipe changes and adds, updates, or retains it in the selected machine file. Without an explicit selection, sync checks ignored `machine/local/.default-machine` and then accepts one unique platform-compatible definition. Configure the local default without committing identity:

```powershell
Set-Content ./machine/local/.default-machine 'main-windows'
```

If more than one compatible machine remains, sync fails and recommends an explicit command.

The selected values are generated only into `build/global/settings.json`. The composer adds their keys to both `workbench.settings.applyToAllProfiles` and `settingsSync.ignoredSettings`, so they apply in every profile on this computer without syncing to another computer. Named-profile settings and `.code-profile` exports remain portable.

Typical values:

- absolute ripgrep path for Todo Tree
- compiler, SDK, engine, or debugger paths
- Kubernetes executable paths
- database client executables
- local performance tuning
- device-specific terminal fonts or GPU settings

The source audit confirmed a working Todo Tree ripgrep path under the current Windows user's WinGet links directory. The personal absolute path is intentionally not published; use this shape locally:

```jsonc
"todo-tree.ripgrep.ripgrep": "C:\\Users\\<username>\\AppData\\Local\\Microsoft\\WinGet\\Links\\rg.exe"
```

Never commit personal absolute paths. Credentials, tokens, connection strings, private hosts, saved connections, certificates, SSH keys, account IDs, and authentication state are excluded private resources and should not be stored in ordinary machine JSONC either.

Because these source files are intentionally ignored, Git does not distribute them. The generated ignored-settings list prevents their setting values from traveling through Settings Sync. Recreate the files from the committed examples on each computer or keep a separate secure private backup. A build for another machine is possible only when that machine's local file is present.

When `ProfileComposer.ps1 sync` reconciles built-in Default/application settings, keys present in the live `settingsSync.ignoredSettings` list are not copied into tracked global settings. A safe path present in the exported named profile is routed to the selected machine definition; sensitive/private resources remain excluded.

See [Complete usage guide](../docs/USAGE.md) for setup, ignore verification, portability, and import guidance.
