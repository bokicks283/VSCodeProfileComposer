# Profile plan

## Immediate core profiles

1. Default
2. C++
3. Unreal Engine
4. Web
5. Python

Default already handles everyday PowerShell, Bash/Zsh shell scripts, and Windows batch files through Suggested Baseline.

## Available advanced profile

- PowerShell Development = Suggested Baseline + PowerShell

Use it for module authoring, Command Explorer, dedicated Pester/PSScriptAnalyzer workflows, advanced debugging, administration tooling, or publishing—not for ordinary script editing.

## Near-term profiles

- Flask = Suggested Baseline + Python + Web + future Flask
- Web + Database = Suggested Baseline + Web + future Database
- Python + Database = Suggested Baseline + Python + future Database

## Later profiles and components

- PHP
- Java
- Game Modding
- Minecraft Modding
- Containers / DevOps
- C#
- Unity
- SQL Server
- MongoDB
- Data Science / Jupyter
- Windows / Microsoft administration

## Unresolved questions

- Which measurement-pending global extensions earn baseline placement?
- Does the Microsoft PowerShell extension create a meaningful measured Default-profile cost in representative workspaces?
- Should ESLint and Tailwind split from Web after MVP validation?
- Which Python formatter/linter stack should own save formatting?
- Should HLSL Tools and C++ Dev Tools be mandatory in Unreal?
- Which Unreal INI solution handles Unreal operators safely?
- Which database clients should be Default-only versus focused components?
- Which advanced Pester, PSScriptAnalyzer, module-publishing, or administration settings belong in PowerShell Development?

## Manual validation order

1. Suggested Baseline and Default in a small mixed repository, including common shell files.
2. Default cold-start measurements.
3. C++ in a normal native C++ repository.
4. Unreal in the primary Unreal workspace.
5. Web in a current Vite/React or Docusaurus repository.
6. Python in a current automation or service repository.
7. PowerShell Development only when advanced module, testing, analysis, debugging, or administration work needs validation.
8. Add near-term composites only after the core component profiles are stable.
