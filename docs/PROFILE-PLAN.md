# Profile plan

## Immediate core profiles

1. Main
2. C++
3. Unreal Engine
4. Web
5. Python
6. Bokicks Labs React
7. Project Zomboid Modding

Main is the shared foundation for every profile and already handles everyday PowerShell, Bash/Zsh shell scripts, Windows batch files, and the user's cross-profile extensions. It intentionally excludes database tooling.

The standalone C++ profile composes `main + cpp + cmake + makefile`. The
Unreal Engine profile composes `main + cpp + csharp + unreal`, so it receives
general C/C++ intelligence, debugging, documentation, C# support for
UnrealBuildTool rules, and agent symbol support without activating CMake or
Makefile project discovery.

The Bokicks Labs React profile composes `main + web + react` for the current
React 19, TypeScript 5, Vite 8, Tailwind CSS 4 portfolio at
`C:\Users\Rim28\Projects\personal-portfolio`. The Project Zomboid Modding
profile composes `main + web + lua + project-zomboid`; Web is intentional
because the planned Lua mod also edits a browser-facing page.

## Current rollout status

The 2026-07-29 automated and read-only Main health check is complete, and the
live Main, C++, and Unreal profiles were reconciled on 2026-08-07. The Unreal
Engine artifact is generated from Main + C++ + C# + Unreal and is ready for
manual import preview and validation in the primary Unreal workspace. See
[Main profile health check](audits/2026-07-29-main-profile-health.md).

## Available opt-in profiles

- PowerShell Development = Main + PowerShell
- Database = Main + Database
- Web + Database = Main + Web + Database
- Python + Database = Main + Python + Database
- SQL Server = Main + Database + SQL Server
- MongoDB = Main + Database + MongoDB

The two project-focused profiles are available now:

- Bokicks Labs React = Main + Web + React
- Project Zomboid Modding = Main + Web + Lua + Project Zomboid

Use PowerShell Development for module authoring, Command Explorer, dedicated Pester/PSScriptAnalyzer workflows, advanced debugging, administration tooling, or publishing—not for ordinary script editing.

Use database profiles only when database editing, querying, schema work, migration work, or administration is expected.

## Near-term compositions

- Flask + Database = Main + Python + Web + future Flask + Database
- PHP + Database = Main + future PHP + Web + Database
- Python + PostgreSQL = Main + Python + Database + future PostgreSQL

These remain planning examples until their missing components contain reviewed configuration.

## Future work-profile examples

```text
Backend Work
= Main
+ Python
+ Flask
+ Database
+ PostgreSQL
+ Containers
```

```text
Enterprise Work
= Main
+ C#
+ Web
+ Database
+ SQL Server
+ Azure
```

These are composition examples only. Employer-specific settings, connections, accounts, and tools must not be added to personal Main.

## Later profiles and components

- Flask
- PHP
- PostgreSQL
- MySQL / MariaDB
- SQLite
- Java
- Additional game-modding ecosystems
- Minecraft Modding
- Containers / DevOps
- Unity
- Data Science / Jupyter
- Windows / Microsoft administration

No empty vendor component is created without real reviewed content.

## Unresolved questions

- Which measurement-pending global extensions earn shared Main placement?
- Does the Microsoft PowerShell extension create a meaningful measured shared-profile cost in representative workspaces?
- Should ESLint and Tailwind split from Web after MVP validation?
- Which Python formatter/linter stack should own save formatting?
- Should HLSL Tools and C++ Dev Tools be mandatory in Unreal?
- Which Unreal INI solution handles Unreal operators safely?
- Should SQLTools remain the generic database client?
- Which PostgreSQL, MySQL/MariaDB, and SQLite extensions should own future vendor components?
- Should SQL Server use only the official MSSQL extension or also a SQLTools driver in selected profiles?
- What is the intended ownership of the previous `mdb.mcp.server` preference?
- Which advanced Pester, PSScriptAnalyzer, module-publishing, or administration settings belong in PowerShell Development?

## Manual validation order

Import each generated `.code-profile` into a new, clearly named test profile and review the selected resources before creating it. Do not replace the active Default profile during initial validation.

1. Main in a small mixed repository, including common shell files — automated
   and read-only configuration comparison complete; final live cleanup remains.
2. Main cold-start measurements.
3. C++ in a normal native C++ repository.
4. Unreal in the primary Unreal workspace — generated artifact ready for
   manual import and runtime validation.
5. Web in a current Vite/React or Docusaurus repository.
6. Python in a current automation or service repository.
7. Database in a disposable local SQL workspace with no saved production connection.
8. SQL Server and MongoDB only when their vendor workflows are needed.
9. PowerShell Development only when advanced module, testing, analysis, debugging, or administration work needs validation.
10. Add future composites only after the owning components are stable.
