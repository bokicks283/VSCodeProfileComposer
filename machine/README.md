# Machine-local settings

Copy the matching example into `machine/local/` and replace placeholders locally. Files under `machine/local/` are ignored.

Apply the local file explicitly during composition:

```powershell
pwsh ./scripts/Compose-Profile.ps1 -Profile unreal -Platform windows -MachineFile ./machine/local/windows.jsonc
```

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
