# Project Zomboid

## Purpose

Adds Build 42 Project Zomboid authoring and project-management support on top
of the reusable Lua component. Recipes that also edit a browser-facing page
should explicitly compose the Web component.

## Extensions

- `cyberbobjr.pz-syntax-extension`: Build 42 syntax highlighting, navigation,
  formatting, and diagnostics for Project Zomboid item, recipe, fixing, and
  craft-recipe script files.
- `escapepz.pzstudio`: Project Zomboid project scaffolding, documentation,
  libraries, builds, translations, and optional Workshop deployment.

## Standalone profile recipe

```yaml
name: Project Zomboid Modding
components:
  - main
  - lua
  - project-zomboid
```

The repository's current Project Zomboid recipe also includes `web` because
the planned mod edits a browser-facing page.

## Safety and ownership

PZ Studio's Build and Watch commands can deploy into a Workshop directory, and
its Clean/Delete commands change generated project content. Configure and
review the project output directory before using them. Do not put a local game
path, Workshop path, account, or deployment target in this portable component.

The Project Zomboid install path used by script navigation is machine- or
workspace-owned. The extension's default `C:\Program Files (x86)` path is not
portable and may not match a Steam library on another drive.
