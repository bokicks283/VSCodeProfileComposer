# Machine-local settings

Copy the matching example into `machine/local/`, give it a stable computer ID, and replace placeholders locally. Files under `machine/local/` are ignored.

For example:

```powershell
Copy-Item ./machine/windows.example.jsonc ./machine/local/main-windows.jsonc
Copy-Item ./machine/windows.example.jsonc ./machine/local/gaming-server.jsonc
pwsh ./scripts/Compose-Profile.ps1 -ListMachines
pwsh ./scripts/Compose-Profile.ps1 -Profile unreal -Platform windows -Machine main-windows
```

The filename without `.jsonc` is the `-Machine` ID. This makes the intended target explicit and records it in the manifest. `-MachineFile` remains a backward-compatible escape hatch; do not use both switches together.

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

Never commit credentials, tokens, connection strings, private hosts, or personal absolute paths.

Because these source files are intentionally ignored, Git does not distribute them. The generated ignored-settings list prevents their setting values from traveling through Settings Sync. Recreate the files from the committed examples on each computer or keep a separate secure private backup. A build for another machine is possible only when that machine's local file is present.

See [Complete usage guide](../docs/USAGE.md) for setup, ignore verification, portability, and import guidance.
