#!/bin/bash
# uninstall.sh
# Claude Code Monitor - Uninstallation Script

set -e

CLAUDE_DIR="$HOME/.claude"
APP_DIR="$HOME/.claude/claude-code-helper"
PLIST_PATH="$HOME/Library/LaunchAgents/com.claude.monitor.plist"

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

# Stop and unload LaunchAgent
if [ -f "$PLIST_PATH" ]; then
    echo -e "${YELLOW}Stopping LaunchAgent daemon...${NC}"
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm "$PLIST_PATH"
    echo -e "${GREEN}✓ LaunchAgent removed${NC}"
fi

# Remove Claude Code Hooks configuration
echo ""
echo -e "${YELLOW}Removing Claude Code Hooks configuration...${NC}"

CLAUDE_SETTINGS="$HOME/.claude/settings.json"

if [ -f "$CLAUDE_SETTINGS" ]; then
    # Check if hooks exist
    if grep -q '"hooks"' "$CLAUDE_SETTINGS" 2>/dev/null; then
        # Backup current settings
        cp "$CLAUDE_SETTINGS" "${CLAUDE_SETTINGS}.uninstall_backup"
        echo -e "${BLUE}  Backed up settings to ${CLAUDE_SETTINGS}.uninstall_backup${NC}"

        # Use Python to remove hooks
        SETTINGS_FILE="$CLAUDE_SETTINGS" python3 << 'EOF'
import json
import sys
import os

settings_file = os.environ['SETTINGS_FILE']

try:
    # Read current settings
    with open(settings_file, 'r') as f:
        settings = json.load(f)

    # Remove hooks if they exist
    if 'hooks' in settings:
        # Check if hooks contain our monitor scripts
        hooks = settings.get('hooks', {})
        has_monitor_hooks = False

        for hook_type in ['SessionStart', 'Stop', 'Notification']:
            if hook_type in hooks:
                for hook_config in hooks[hook_type]:
                    for hook in hook_config.get('hooks', []):
                        if 'record.sh' in hook.get('command', ''):
                            has_monitor_hooks = True
                            break

        if has_monitor_hooks:
            del settings['hooks']

            # Write back
            with open(settings_file, 'w') as f:
                json.dump(settings, f, indent=2)
                f.write('\n')

            print("✓ Hooks removed from settings.json")
        else:
            print("ℹ️  No monitor hooks found in settings.json")
    else:
        print("ℹ️  No hooks configuration found")

except Exception as e:
    print(f"⚠️  Error: {e}")
    sys.exit(1)
EOF

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Claude Code Hooks removed from $CLAUDE_SETTINGS${NC}"
        else
            echo -e "${YELLOW}⚠️  Could not automatically remove hooks${NC}"
            echo -e "${YELLOW}  Please manually check: $CLAUDE_SETTINGS${NC}"
            echo -e "${YELLOW}  Backup available at: ${CLAUDE_SETTINGS}.uninstall_backup${NC}"
        fi
    else
        echo -e "${BLUE}  No hooks configuration found in settings.json${NC}"
    fi
else
    echo -e "${BLUE}  Settings file not found${NC}"
fi

# Backup database before deletion
DB_PATH="$CLAUDE_DIR/monitor.db"
echo ""
echo -e "${YELLOW}Backing up database...${NC}"

if [ -f "$DB_PATH" ]; then
    BACKUP_FILE="$CLAUDE_DIR/monitor.db.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$DB_PATH" "$BACKUP_FILE"
    echo -e "${GREEN}✓ Database backed up to: $BACKUP_FILE${NC}"

    # Remove database
    rm "$DB_PATH"
    echo -e "${GREEN}✓ Database removed${NC}"
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
echo -e "  ✓ LaunchAgent daemon (if installed)"
echo -e "  ✓ Claude Code Hooks configuration (from settings.json)"
echo -e "  ✓ Shell aliases"
echo -e "  ✓ Database: $DB_PATH"
echo -e "  ✓ Application directory: $APP_DIR/"
echo ""

echo -e "${BLUE}Preserved:${NC}"
echo -e "  ✓ ~/.claude directory (Claude Code official directory)"
echo -e "  ✓ settings.json (hooks removed, other settings intact)"
echo ""

echo -e "${BLUE}Backup files created:${NC}"
if [ -f "$BACKUP_FILE" ]; then
    echo -e "  Database: $BACKUP_FILE"
fi
if [ -f "${CLAUDE_SETTINGS}.uninstall_backup" ]; then
    echo -e "  Settings: ${CLAUDE_SETTINGS}.uninstall_backup"
fi
for RC_FILE in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "${RC_FILE}.backup" ]; then
        echo -e "  Shell: ${RC_FILE}.backup"
    fi
done
echo ""

echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Restart Claude Code to clear hooks"
echo -e "  2. Restart your terminal or run:"
echo -e "     ${BLUE}source ~/.zshrc${NC}  (or ~/.bashrc)"
echo ""
