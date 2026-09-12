# LAMP + LEMP Linux handoff prompt

Paste the prompt below into a Codex task running inside the Linux distro after
this repository and its `lamp-lemp` profile changes are available there.

```text
You are working on my Linux distro. Finish the Linux-specific setup and
verification for the VSCodeProfileComposer profile named "LAMP + LEMP".

Start by reading the repository's AGENTS.md/agents.md instructions and relevant
documentation. Inspect the active checkout, current branch, Git status,
distribution identity and version, CPU architecture, shell, installed VS Code
variant/version, and the currently installed PHP, Composer, Apache/httpd,
NGINX, MySQL/MariaDB, PHP-FPM, Xdebug, and database-client packages. Do not
assume Debian/Ubuntu package names or paths: detect whether this is Debian,
Ubuntu, Fedora/RHEL, Arch, openSUSE, or another family and adapt accordingly.

Keep the VS Code work repository-only until I explicitly approve live profile
import or package installation. Do not mutate VS Code user data, Settings Sync,
profiles, extensions, system packages, services, firewall rules, databases,
users, credentials, TLS material, or privileged files during discovery and
planning. Never print secrets. Treat database connections, passwords, socket
paths, certificates, PHP executable paths, and distro-specific service paths as
machine-local or workspace-owned, not portable component settings.

Validate the repository first:

1. Confirm the `lamp-lemp` recipe composes `main`, `web`, `php`, `database`,
   `mysql-mariadb`, and `apache-nginx` in that order.
2. Run the composer validation in strict mode.
3. Compose `lamp-lemp` for the Linux platform and verify the generated
   `build/profiles/lamp-lemp/LAMP-LEMP.code-profile` structure, settings,
   extension IDs, and deterministic Apache/NGINX file associations.
4. Run the repository documentation validation and full Pester suite. Report
   exact commands, pass/fail counts, and any warnings.

Then produce a distro-specific implementation plan for a safe local
development stack. Cover both choices without running both web servers on the
same port:

- LAMP: Apache/httpd + PHP integration + MySQL or MariaDB.
- LEMP: NGINX + PHP-FPM + MySQL or MariaDB.

The plan must identify exact detected package names, service names,
configuration roots, enabled-site mechanism if any, PHP-FPM socket or TCP
endpoint, log locations, config-test commands, service-status commands, and
which database engine is already installed or should be selected. Prefer the
distro's supported packages and least-privilege local-development defaults.
Include rollback steps before any privileged or service-changing action.

Before making system changes, show me:

- the detected facts;
- what is already usable;
- the exact proposed package/service/config changes;
- whether Apache or NGINX will be active by default;
- whether MySQL or MariaDB will be used;
- backup and rollback paths;
- the commands you want to run with sudo;
- tests that will prove PHP execution, database connectivity, web-server config
  validity, Xdebug availability, and a clean service state.

Stop for my explicit approval before the first package install/removal, sudo
write, service enable/start/stop/restart, firewall change, database security
operation, user/group change, or live VS Code profile import. After approval,
make only the reviewed changes, preserve backups, and verify each boundary.

For VS Code delivery, use the repository-generated Linux `.code-profile` and
VS Code's supported Profiles import UI. If UI automation is unavailable, leave
the final import as a concise manual step. Do not reconstruct or edit VS Code's
private profile database. Review the import contents before creation. Keep
workspace-specific `launch.json` Xdebug path mappings, PHP/Composer versions,
framework tools, database connections, and server configuration in the target
project rather than this portable profile.

Finish with a concise evidence-backed report separating confirmed results from
remaining manual steps. Do not claim the stack works end to end unless config
tests pass and a controlled local HTTP request executes PHP successfully; do
not claim database integration unless a least-privilege test connection and
query succeed.
```
