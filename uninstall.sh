#!/bin/bash
# uninstall.sh
# Claude Code Monitor - Uninstallation Script

set -e

CLAUDE_DIR="$HOME/.claude"
APP_DIR="$HOME/.claude/claude-code-helper"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Claude Code Monitor - Uninstallation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Remove Claude Code Hooks configuration
echo ""
echo -e "${YELLOW}Removing Claude Code Hooks configuration...${NC}"

CLAUDE_SETTINGS="$HOME/.claude/settings.json"

if [ -f "$CLAUDE_SETTINGS" ]; then
    cp "$CLAUDE_SETTINGS" "${CLAUDE_SETTINGS}.uninstall_backup"
    echo -e "${BLUE}  Backed up settings to ${CLAUDE_SETTINGS}.uninstall_backup${NC}"

    SETTINGS_FILE="$CLAUDE_SETTINGS" APP_DIR="$APP_DIR" python3 << 'EOF'
import json
import os
import sys
from pathlib import Path

settings_file = os.environ['SETTINGS_FILE']
app_dir = os.environ['APP_DIR']

try:
    with open(settings_file, "r", encoding="utf-8") as f:
        settings = json.load(f)
except Exception:
    sys.exit(0)

hooks = settings.get("hooks")
if not isinstance(hooks, dict):
    sys.exit(0)

removed = False

hook_commands = {
    "SessionStart": {f"{app_dir}/scripts/record.sh start"},
    "UserPromptSubmit": {f"{app_dir}/scripts/record.sh user_prompt"},
    "Stop": {f"{app_dir}/scripts/record.sh stop"},
    "Notification": {f"{app_dir}/scripts/record.sh notification"},
}

for event in list(hooks.keys()):
    entries = hooks.get(event)
    if not isinstance(entries, list):
        continue

    new_entries = []
    for entry in entries:
        hooks_list = entry.get("hooks")
        if not isinstance(hooks_list, list):
            new_entries.append(entry)
            continue

        filtered = [
            hook
            for hook in hooks_list
            if not (
                hook.get("type") == "command"
                and isinstance(hook.get("command"), str)
                and hook["command"] in hook_commands.get(event, set())
            )
        ]

        if len(filtered) != len(hooks_list):
            removed = True

        if filtered:
            entry = dict(entry)
            entry["hooks"] = filtered
            new_entries.append(entry)

    if new_entries:
        hooks[event] = new_entries
    else:
        if entries:
            removed = True
        hooks.pop(event, None)

if removed:
    if hooks:
        settings["hooks"] = hooks
    else:
        settings.pop("hooks", None)

    with open(settings_file, "w", encoding="utf-8") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")

    print("✓ settings.json 中的监控命令已移除")
else:
    print("ℹ️  settings.json 中未发现监控命令")
EOF
else
    echo -e "${BLUE}  Settings file not found${NC}"
fi

# 清理遗留的插件目录（兼容旧版本）
if [ -d "$HOME/.claude/plugins/claude-code-helper" ]; then
    rm -rf "$HOME/.claude/plugins/claude-code-helper"
    echo -e "${BLUE}  Removed legacy plugin directory ~/.claude/plugins/claude-code-helper${NC}"
fi

# Keep database (data is valuable now)
DB_PATH="$CLAUDE_DIR/monitor.db"
echo ""
echo -e "${YELLOW}Checking database...${NC}"

if [ -f "$DB_PATH" ]; then
    echo -e "${GREEN}✓ Database preserved: $DB_PATH${NC}"
    echo -e "${BLUE}  ℹ️  To remove database, use: claude-flush-db${NC}"
else
    echo -e "${BLUE}ℹ️  Database file not found${NC}"
fi

# Remove application directory
echo ""
echo -e "${YELLOW}Removing application directory...${NC}"

if [ -d "$APP_DIR" ]; then
    rm -rf "$APP_DIR"
    echo -e "${GREEN}✓ Application directory removed: $APP_DIR${NC}"
else
    echo -e "${BLUE}ℹ️  Application directory not found${NC}"
fi

# Remove shell aliases
echo ""
echo -e "${YELLOW}Removing shell aliases...${NC}"

for RC_FILE in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$RC_FILE" ]; then
        # Remove Claude Code Monitor section
        if grep -q "# Claude Code Monitor aliases" "$RC_FILE" 2>/dev/null; then
            # Create backup
            cp "$RC_FILE" "${RC_FILE}.backup"

            # Remove aliases (from comment line to the last alias)
            sed -i.tmp '/# Claude Code Monitor aliases/,/alias claude-query=/d' "$RC_FILE"
            rm -f "${RC_FILE}.tmp"

            echo -e "${GREEN}✓ Aliases removed from $(basename $RC_FILE)${NC}"
            echo -e "${BLUE}  Backup saved: ${RC_FILE}.backup${NC}"
        fi
    fi
done

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Uninstallation Complete${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}What was removed:${NC}"
echo -e "  ✓ Claude Code Hooks configuration (from settings.json)"
echo -e "  ✓ Shell aliases"
echo -e "  ✓ Application directory: $APP_DIR/"
echo ""

echo -e "${BLUE}Preserved:${NC}"
echo -e "  ✓ ~/.claude directory (Claude Code official directory)"
echo -e "  ✓ settings.json (hooks removed, other settings intact)"
echo -e "  ✓ Database: $DB_PATH (contains valuable session history)"
echo ""

echo -e "${BLUE}Backup files created:${NC}"
if [ -f "${CLAUDE_SETTINGS}.uninstall_backup" ]; then
    echo -e "  Settings: ${CLAUDE_SETTINGS}.uninstall_backup"
fi
for RC_FILE in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "${RC_FILE}.backup" ]; then
        echo -e "  Shell: ${RC_FILE}.backup"
    fi
done
echo ""

echo -e "${YELLOW}Note:${NC}"
echo -e "  Database was preserved. To remove it, run: ${BLUE}claude-flush-db${NC}"
echo ""

echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Restart Claude Code to clear hooks"
echo -e "  2. Restart your terminal or run:"
echo -e "     ${BLUE}source ~/.zshrc${NC}  (or ~/.bashrc)"
echo ""
