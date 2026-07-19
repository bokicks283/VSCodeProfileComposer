# Profile plan

## Immediate profiles

1. Default
2. C++
3. Unreal Engine
4. PowerShell
5. Web
6. Python

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

## Unresolved questions

- Which measurement-pending global extensions earn baseline placement?
- Should ESLint and Tailwind split from Web after MVP validation?
- Which Python formatter/linter stack should own save formatting?
- Should HLSL Tools and C++ Dev Tools be mandatory in Unreal?
- Which Unreal INI solution handles Unreal operators safely?
- Which database clients should be Default-only versus focused components?

## Manual validation order

1. Suggested Baseline and Default in a small repository.
2. Default cold-start measurements.
3. C++ in a normal native C++ repository.
4. Unreal in the primary Unreal workspace.
5. PowerShell in the audit/system-administration workflows.
6. Web in a current Vite/React or Docusaurus repository.
7. Python in a current automation or service repository.
8. Add near-term composites only after the component profiles are stable.
