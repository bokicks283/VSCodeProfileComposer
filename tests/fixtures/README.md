# VS Code profile schema fixture

`vscode-1.129.1-minimal.code-profile` is a sanitized, minimal schema fixture. Its harmless resource values were used in a disposable VS Code profile, and its structure was verified against the installed VS Code 1.129.1 source at commit `8a7abeba6e03ea3af87bfbce9a1b7e48fed567b8`.

The raw UI export was not retained. The fixture is deliberately hand-authored from the verified source contract so it contains no account state, identifiers, personal paths, installed-extension inventory, or UI state. It covers only:

- one setting;
- one custom keybinding with Windows platform value `3`;
- one extension identifier;
- a profile display name.

The relevant source is `src/vs/workbench/services/userDataProfile/browser/userDataProfileImportExportService.ts` and its settings, keybindings, and extensions resource implementations at that commit.
