# Python

## Purpose

General Python language intelligence, debugging, environment management, type checking, and reviewed editor behavior.

## Belongs here

Python extension settings, Pylance behavior, environment behavior, testing defaults that are broadly applicable, and Python-owned extensions.

## Does not belong here

Personal interpreter paths, virtual environment paths, Flask-only behavior, Jupyter/R configuration, deployment secrets, or project package indexes.

## Standalone profile recipe

```yaml
name: Python
components:
  - suggested-baseline
  - python
```

## Reused by

Python and future Flask, FastAPI, Django, Python Automation, Data Science, and Python + Database profiles.

## Portability classification

Current settings use extension behavior and package names only; no interpreter or environment path is committed.

## Platform concerns

Python launcher and shell behavior differ by OS but remain outside the portable component.

## Machine concerns

Interpreter paths, Conda/venv roots, package mirrors, credentials, and hardware-specific analysis tuning stay local.

## Workspace concerns

The repository should select its interpreter, test framework, formatter/linter, environment activation, and framework-specific behavior.

## Performance concerns

`diagnosticMode` remains `openFilesOnly` to limit analysis cost. Deep package indexing is retained only for the reviewed high-use libraries and frameworks.

## Deferred decisions

Formatter ownership, Ruff/Pylint/Mypy, Flask-specific configuration, Django, Jupyter, and test-framework defaults.
