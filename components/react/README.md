# React

## Purpose

Adds modern React 17-19 and TypeScript component/hook snippets on top of the
framework-neutral Web component. The current Bokicks Labs portfolio uses React
19, TypeScript 5, Vite 8, Tailwind CSS 4, and ESLint flat configuration.

## Belongs here

React-specific authoring aids and portable settings that should be shared by
React recipes.

## Does not belong here

Generic HTML/CSS/JavaScript/TypeScript behavior, Tailwind, ESLint, browser
paths, Node installation paths, Vite project configuration, or repository
formatting policy.

## Extension

- `r5n.es-js-snippets`: maintained React 17-19, React Router, TypeScript, and
  hook snippets. It replaces the legacy `dsznajder.es7-react-js-snippets`
  listing and avoids old snippets that insert an unnecessary React import.

## Standalone profile recipe

```yaml
name: React
components:
  - main
  - web
  - react
```

## Reused by

The Bokicks Labs React profile and future React applications. React Native,
Next.js, browser testing, and database tooling remain separate opt-in concerns.

## Workspace concerns

The repository owns its React version, Vite configuration, path aliases,
ESLint rules, Tailwind integration, formatter policy, test runner, and Node
version. The composer does not duplicate those decisions.
