# Lua

## Purpose

Provides reusable Lua language intelligence and an explicit deterministic
formatter without enabling automatic source rewrites.

## Extensions

- `sumneko.lua`: Lua Language Server support for completion, navigation,
  diagnostics, annotations, and Lua 5.1 through current Lua versions.
- `JohnnyMorganz.stylua`: deterministic Lua formatter. It is selected as the
  default formatter, but format-on-save remains a workspace decision.

## Standalone profile recipe

```yaml
name: Lua
components:
  - main
  - lua
```

## Reused by

Project Zomboid modding and future Lua-based tools or games.

## Workspace concerns

The repository owns the target Lua runtime, external library definitions,
diagnostic globals, formatting rules, and generated or vendor folder
exclusions. Game-specific APIs do not belong in this generic component.
