# Repository Guidelines

## Project Structure & Module Organization
- Core automation scripts (`install.sh`, `uninstall.sh`, `diagnose.sh`, `test.sh`) live at the repo root.
- Operational logic resides in `scripts/` (`init.sh`, `record.sh`, `cleanup.sh`, `query.sh`). Treat these as the single source for hook behaviour.
- Docs and runbooks (e.g., `docs/INSTALL.md`, `docs/DEBUG_GUIDE.md`, `CLAUDE.md`) explain installation, debugging, and operating procedures.
- `backups/` stores the full-featured script snapshots; copy them back into `scripts/` when you are done with the debug-only build.
- Scenario-specific test fixtures (`test_hooks*.sh`, `test_notify.sh`) and status dashboards (`STATUS.md`) remain in the top level for quick access.

## Build, Test, and Development Commands
- `bash scripts/init.sh`: Prepare the `~/.claude` workspace and logging layout.
- `bash install.sh [--with-daemon]`: Install hooks and optional LaunchAgent refresher.
- `bash test_hooks_simple.sh`: Minimal hook smoke-test; confirms trigger wiring.
- `bash test.sh`: Comprehensive regression suite; spins up `test_monitor.db`.
- `bash diagnose.sh`: Environment check covering permissions, SQLite, and LaunchAgent state.
- `tail -f ~/.claude/logs/hook_debug.log`: Observe live hook events while iterating.

## Coding Style & Naming Conventions
- Target Bash 3.2; keep shebangs as `#!/bin/bash` and enable `set -e` (layer `-u`/`-o pipefail` when stable).
- Prefer four-space indentation inside blocks, uppercase for constant-like vars (`CLAUDE_DIR`), and snake_case for helpers (`setup_test_env`).
- Quote variable expansions, use `[[ ... ]]` for conditionals, and group reusable logic near the top. Run `shellcheck` before committing complex changes.

## Testing Guidelines
- Tests assume a writable `~/.claude` tree and `sqlite3` on `PATH`.
- Follow the `test_*.sh` naming pattern; make new scripts idempotent.
- Record manual verification (e.g., LaunchAgent behaviour) in `STATUS.md` or an appropriate doc entry.

## Commit & Pull Request Guidelines
- Use concise, imperative commit subjects (`Fix daemon cleanup race`).
- PRs should call out touched scripts/docs, manual test evidence, and relevant log excerpts or screenshots.
- Cross-link related docs (e.g., `docs/DEBUG_GUIDE.md`) and confirm changes preserve `~/.claude` paths and permissions.

## Configuration & Safety Notes
- Repo scripts edit `~/.claude/settings.json`, `monitor.db`, and LaunchAgent entries—test in a sandboxed profile before shipping.
- Back up `backups/` artifacts prior to overwriting, and restore production-ready scripts with `cp backups/scripts_backup_*/\*.sh scripts/` when graduating from debug mode.
