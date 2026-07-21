# Profile plan

## Immediate core profiles

1. Default
2. C++
3. Unreal Engine
4. Web
5. Python

Default already handles everyday PowerShell, Bash/Zsh shell scripts, and Windows batch files through Suggested Baseline. It intentionally excludes database tooling.

## Available opt-in profiles

- PowerShell Development = Suggested Baseline + PowerShell
- Database = Suggested Baseline + Database
- Web + Database = Suggested Baseline + Web + Database
- Python + Database = Suggested Baseline + Python + Database
- SQL Server = Suggested Baseline + Database + SQL Server
- MongoDB = Suggested Baseline + Database + MongoDB

Use PowerShell Development for module authoring, Command Explorer, dedicated Pester/PSScriptAnalyzer workflows, advanced debugging, administration tooling, or publishing—not for ordinary script editing.

Use database profiles only when database editing, querying, schema work, migration work, or administration is expected.

## Near-term compositions

- Flask + Database = Suggested Baseline + Python + Web + future Flask + Database
- PHP + Database = Suggested Baseline + future PHP + Web + Database
- Python + PostgreSQL = Suggested Baseline + Python + Database + future PostgreSQL

These remain planning examples until their missing components contain reviewed configuration.

## Future work-profile examples

```text
Backend Work
= Suggested Baseline
+ Python
+ Flask
+ Database
+ PostgreSQL
+ Containers
```

```text
Enterprise Work
= Suggested Baseline
+ C#
+ Web
+ Database
+ SQL Server
+ Azure
```

These are composition examples only. Employer-specific settings, connections, accounts, and tools must not be added to personal Default.

## Later profiles and components

- Flask
- PHP
- PostgreSQL
- MySQL / MariaDB
- SQLite
- Java
- Game Modding
- Minecraft Modding
- Containers / DevOps
- C#
- Unity
- Data Science / Jupyter
- Windows / Microsoft administration

No empty vendor component is created without real reviewed content.

## Unresolved questions

- Which measurement-pending global extensions earn baseline placement?
- Does the Microsoft PowerShell extension create a meaningful measured Default-profile cost in representative workspaces?
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

1. Suggested Baseline and Default in a small mixed repository, including common shell files.
2. Default cold-start measurements.
3. C++ in a normal native C++ repository.
4. Unreal in the primary Unreal workspace.
5. Web in a current Vite/React or Docusaurus repository.
6. Python in a current automation or service repository.
7. Database in a disposable local SQL workspace with no saved production connection.
8. SQL Server and MongoDB only when their vendor workflows are needed.
9. PowerShell Development only when advanced module, testing, analysis, debugging, or administration work needs validation.
10. Add future composites only after the owning components are stable.
