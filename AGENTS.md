# Repository Guidelines

## Project Structure & Module Organization
This repository packages the Claude Code Monitor automation. Root脚本如 `install.sh`、`uninstall.sh`、`test.sh` 负责安装、卸载与回归检查。核心 hook 逻辑位于 `scripts/`（`init.sh` 建库、`record.sh` 写入会话、`query.sh` 输出报表）。贡献者文档存放在 `docs/` 及 `CLAUDE.md`。运行时资产位于 `~/.claude/claude-code-helper/`，日志写入 `logs/`，数据库 `monitor.db` 保存在父目录 `~/.claude/`。全局 hook 通过用户级 `~/.claude/settings.json` 下发，安装时会扫描 `CLAUDE_HELPER_SCAN_ROOTS`（默认 `~/Documents`）内的 `.claude/settings*.json` 自动补齐。

## Build, Test, and Development Commands
Run `bash scripts/init.sh` to bootstrap a local SQLite schema when iterating outside the installer. Run `./install.sh [--with-daemon]` 复制脚本、更新 `~/.claude/settings.json` 并批量修补 `CLAUDE_HELPER_SCAN_ROOTS` 路径下的 `.claude/settings*.json`。使用 `./uninstall.sh` 可备份数据库、移除用户级/工程级 hook，并清理历史扫描记录。`./test.sh` 会初始化 `test_monitor.db` 并验证表、索引、触发器。调试时可通过 `tail -f ~/.claude/claude-code-helper/logs/monitor.log` 观察事件。

## Coding Style & Naming Conventions
All scripts target Bash 3.2 with `#!/bin/bash` shebangs and `set -e`; escalate to `set -u -o pipefail` only after verifying behaviour. Indent blocks with four spaces, reserve uppercase for constant-style variables (`CLAUDE_DIR`), and prefer snake_case helpers (`setup_test_env`). Use `[[ … ]]` conditionals, quote expansions, and keep reusable helpers near the top. Run `shellcheck scripts/*.sh install.sh uninstall.sh` before submitting substantial changes.

## Testing Guidelines
Testing relies on `sqlite3` being available and a writable `~/.claude` tree. Add new test harnesses as `test_*.sh` scripts that reset their fixtures and leave `monitor.db` intact. Document any manual verification (e.g., LaunchAgent behaviour or notification flows) in `STATUS.md` or an appropriate doc in `docs/`.

## Commit & Pull Request Guidelines
Write short, imperative commit subjects (`Add record event guard`). In PRs, summarize affected scripts or docs, call out manual test evidence, and link relevant issues or logs. Cross-reference supporting guides (for example `docs/PROJECT_SUMMARY.md` or `CLAUDE.md`) so the next maintainer can trace rationale. Confirm that hooks still target the `~/.claude` namespace and that database migrations include forward/backward instructions.

## Security & Configuration Tips
Repository 脚本会写入 `~/.claude/settings.json`、`CLAUDE_HELPER_SCAN_ROOTS` 中的 `.claude/settings*.json`、`monitor.db` 以及可选 LaunchAgent。危险操作请先在隔离环境验证，并在覆盖前备份 `~/.claude/claude-code-helper/backups/`。从备份恢复脚本时注意保留可执行权限。
