# Main versus Extension Library review

This is a point-in-time review from 2026-07-21. The live VS Code profile named `Main` was queried read-only with `code --profile Main --list-extensions`; no extension or profile data was changed.

Repository follow-up through 2026-07-29: the renamed Main component now owns 36 extensions and all components own 52 unique extensions. The live counts below remain the original point-in-time evidence and have not been silently rewritten.

## Counts

- Live `Main`: 33 extensions
- Repository `default` component at audit time: 32 extensions
- All repository components: 48 unique extensions
- Historical Extension Library Staging inventory: 150 extensions
- Historical IDs absent from `Main`: 118
- Historical IDs absent from every repository component: 102

At audit time, live `Main` matched the repository `default` extension set except for one extension:

- `davidanson.vscode-markdownlint`

That extension was not in the 150-ID historical staging export either. Because `Main` was recently signed into Settings Sync, this review did not assume the extra extension was an intentional addition. If it is still wanted after current Main validation, add it to `components/main/extensions.txt` so the repository remains canonical.

## What is actually missing

No historical-only extension is an obvious requirement for every profile. The strongest capability candidates are profile-specific:

- Remote server work: `ms-vscode-remote.remote-ssh` and its Remote Explorer support. This is useful only when VS Code should open and develop directly on an SSH host.
- Containers: `ms-vscode-remote.remote-containers` for Dev Containers and `ms-azuretools.vscode-containers` for container build/manage/debug workflows. Do not restore the older `docker.docker` entry; current Container Tools replaces its language service, management, and debugging functionality.
- Non-Unreal CMake projects: `ms-vscode.cmake-tools`. Unreal's generated build workflow does not require it by default.
- Web testing: `ms-playwright.playwright` and `vitest.explorer`, only for repositories that use those test frameworks.
- Python notebooks/data work: `ms-toolsai.jupyter` and optionally `ms-toolsai.datawrangler`. Jupyter brings its companion keymap/rendering extensions through its own dependency flow, so the full historical bundle should not be declared manually without testing.
- Additional language families: the historical C#/.NET, Java, PHP, R, Unity, embedded, Minecraft, and Processing groups should become focused components only when those workflows return.

## Decision

Keep Main lean during profile validation. The only unexplained difference in the 2026-07-21 live snapshot was `davidanson.vscode-markdownlint`; all other high-value gaps belong in focused components rather than Main. Recheck live state before treating that historical difference as current.

Official references used for the current capability check:

- [Remote - SSH](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-ssh)
- [Container Tools](https://marketplace.visualstudio.com/items?itemName=ms-azuretools.vscode-containers)
- [CMake Tools](https://marketplace.visualstudio.com/items?itemName=ms-vscode.cmake-tools)
- [Jupyter](https://marketplace.visualstudio.com/items?itemName=ms-toolsai.jupyter)
