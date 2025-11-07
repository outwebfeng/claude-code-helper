#!/bin/bash
# install.sh
# Claude Code Monitor - 安装脚本
#
# 功能：自动安装 Claude Code 监控系统的所有组件
# 用法：bash install.sh
#
# 安装内容：
#   1. 复制脚本文件到 ~/.claude/scripts/
#   2. 初始化数据库结构
#   3. 配置 Claude Code Hooks（自动修改 settings.json）
#   4. 添加命令别名到 shell 配置

# 遇到错误立即退出（-e），使用未定义变量报错（-u）
set -e

# ============================================================
# 变量定义
# ============================================================

# 获取脚本所在目录的绝对路径
# ${BASH_SOURCE[0]} 是脚本文件路径
# dirname 获取目录，cd && pwd 获取绝对路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Claude Code 根目录（官方目录，用于存放 settings.json）
CLAUDE_DIR="$HOME/.claude"

# 我们的应用专属目录（所有文件都放这里，便于管理和卸载）
APP_DIR="$HOME/.claude/claude-code-helper"

# ============================================================
# 终端颜色定义（用于美化输出）
# ============================================================
RED='\033[0;31m'      # 红色（错误）
GREEN='\033[0;32m'    # 绿色（成功）
BLUE='\033[0;34m'     # 蓝色（信息）
YELLOW='\033[1;33m'   # 黄色（警告）
NC='\033[0m'          # 无颜色（重置）


# ============================================================
# 显示欢迎信息
# ============================================================
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🚀 Claude Code Monitor Installation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ============================================================
# 步骤 1: 检查系统依赖
# ============================================================
echo -e "${YELLOW}Checking dependencies...${NC}"

# 检查 sqlite3 是否安装（必需，用于数据库操作）
# command -v 检查命令是否存在
# &> /dev/null 将输出重定向到空设备（不显示）
if ! command -v sqlite3 &> /dev/null; then
    echo -e "${RED}❌ Error: sqlite3 is not installed${NC}"
    echo -e "${RED}   Please install: brew install sqlite3${NC}"
    exit 1
fi
echo -e "${GREEN}✓ sqlite3 found${NC}"

# 检查 terminal-notifier 是否安装（必需，用于通知）
if ! command -v terminal-notifier &> /dev/null; then
    echo -e "${RED}❌ Error: terminal-notifier is not installed${NC}"
    echo -e "${RED}   terminal-notifier is required for desktop notifications${NC}"
    echo ""
    if command -v brew &> /dev/null; then
        echo -e "${YELLOW}   Installing terminal-notifier via Homebrew...${NC}"
        brew install terminal-notifier
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ terminal-notifier installed successfully${NC}"
        else
            echo -e "${RED}❌ Failed to install terminal-notifier${NC}"
            echo -e "${RED}   Please install manually: brew install terminal-notifier${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ Homebrew not found${NC}"
        echo -e "${RED}   Please install Homebrew first: https://brew.sh${NC}"
        echo -e "${RED}   Then run: brew install terminal-notifier${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ terminal-notifier found${NC}"
fi

# ============================================================
# 步骤 2: 创建应用目录结构
# ============================================================
echo ""
echo -e "${YELLOW}Creating directory structure...${NC}"

# 创建应用专属目录（-p 参数：递归创建，如果已存在不报错）
mkdir -p "$APP_DIR/scripts"
mkdir -p "$APP_DIR/logs"
mkdir -p "$APP_DIR/backups"
echo -e "${GREEN}✓ Directory structure created at $APP_DIR${NC}"

# ============================================================
# 步骤 3: 复制脚本文件
# ============================================================
echo ""
echo -e "${YELLOW}Copying scripts...${NC}"

# 复制所有 .sh 脚本文件到应用目录
cp "$SCRIPT_DIR/scripts/"*.sh "$APP_DIR/scripts/"
echo -e "${GREEN}✓ Scripts copied${NC}"

# ============================================================
# 步骤 4: 运行数据库初始化
# ============================================================
echo ""
echo -e "${YELLOW}Running initialization...${NC}"

# 运行 init.sh 脚本
# 功能：创建数据库、表、索引、视图、触发器
bash "$APP_DIR/scripts/init.sh"

# ============================================================
# 步骤 5: 设置脚本执行权限
# ============================================================
echo ""
echo -e "${YELLOW}Setting permissions...${NC}"

# 为所有脚本添加可执行权限（chmod +x）
# 755 = rwxr-xr-x（所有者可读写执行，其他人可读执行）
chmod +x "$APP_DIR/scripts/"*.sh
echo -e "${GREEN}✓ Permissions set${NC}"


# ============================================================
# 步骤 6: 配置 Claude Code Hooks（用户级）
# ============================================================
echo ""
echo -e "${YELLOW}Configuring Claude Code Hooks...${NC}"

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# 兼容旧版本：清理遗留的插件目录
LEGACY_PLUGIN_DIR="$HOME/.claude/plugins/claude-code-helper"
if [ -d "$LEGACY_PLUGIN_DIR" ]; then
    rm -rf "$LEGACY_PLUGIN_DIR"
    echo -e "${BLUE}  Removed legacy plugin directory: $LEGACY_PLUGIN_DIR${NC}"
fi

SETTINGS_FILE="$CLAUDE_SETTINGS" APP_DIR="$APP_DIR" TIMESTAMP="$TIMESTAMP" python3 << 'EOF'
import json
import os
import shutil
import sys
from pathlib import Path

settings_path = Path(os.environ['SETTINGS_FILE']).expanduser()
app_dir = Path(os.environ['APP_DIR'])
timestamp = os.environ['TIMESTAMP']

hook_spec = {
    "SessionStart": [
        {"matcher": "startup", "command": f"{app_dir}/scripts/record.sh start"},
        {"matcher": "resume", "command": f"{app_dir}/scripts/record.sh start"},
    ],
    "UserPromptSubmit": [
        {"matcher": None, "command": f"{app_dir}/scripts/record.sh user_prompt"},
    ],
    "Stop": [
        {"matcher": None, "command": f"{app_dir}/scripts/record.sh stop"},
    ],
    "Notification": [
        {"matcher": None, "command": f"{app_dir}/scripts/record.sh notification"},
    ],
}


def ensure_hooks(data: dict) -> bool:
    hooks = data.setdefault("hooks", {})
    changed = False

    for event, specs in hook_spec.items():
        entries = hooks.setdefault(event, [])
        if not isinstance(entries, list):
            entries = []
            hooks[event] = entries

        for spec in specs:
            matcher = spec["matcher"]
            command = spec["command"]

            target_entry = None
            for entry in entries:
                entry_matcher = entry.get("matcher")
                if matcher is None:
                    if entry_matcher in (None, "", "null"):
                        target_entry = entry
                        break
                elif entry_matcher == matcher:
                    target_entry = entry
                    break

            if target_entry is None:
                target_entry = {}
                if matcher is not None:
                    target_entry["matcher"] = matcher
                target_entry["hooks"] = []
                entries.append(target_entry)
                changed = True

            hook_list = target_entry.setdefault("hooks", [])
            if not isinstance(hook_list, list):
                hook_list = []
                target_entry["hooks"] = hook_list
            if not any(
                isinstance(h, dict)
                and h.get("type") == "command"
                and h.get("command") == command
                for h in hook_list
            ):
                hook_list.append({"type": "command", "command": command})
                changed = True

    return changed


if settings_path.exists():
    try:
        existing = json.loads(settings_path.read_text(encoding="utf-8"))
        if not isinstance(existing, dict):
            print("⚠️  settings.json 不是有效的 JSON 对象，已跳过")
            sys.exit(1)
    except Exception as exc:  # noqa: BLE001
        print(f"⚠️  无法读取现有 settings.json: {exc}")
        sys.exit(1)
else:
    existing = {}

if ensure_hooks(existing):
    settings_path.parent.mkdir(parents=True, exist_ok=True)
    if settings_path.exists():
        backup = settings_path.with_name(f"{settings_path.name}.backup.{timestamp}")
        shutil.copy2(settings_path, backup)
        print(f"备份已创建: {backup}")
    settings_path.write_text(json.dumps(existing, indent=2) + "\n", encoding="utf-8")
    print("✓ 已更新 ~/.claude/settings.json 的 hooks")
else:
    print("ℹ️  ~/.claude/settings.json 已包含所需 hooks")
EOF

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠️  Skipped updating ~/.claude/settings.json, please check manually${NC}"
fi

# ============================================================
# 步骤 7: 添加 Shell 命令别名
# ============================================================
echo ""
echo -e "${YELLOW}Adding shell aliases...${NC}"

# 检测使用哪个 shell 配置文件
SHELL_RC=""
if [ -f "$HOME/.zshrc" ]; then
    SHELL_RC="$HOME/.zshrc"      # Zsh (macOS 默认)
elif [ -f "$HOME/.bashrc" ]; then
    SHELL_RC="$HOME/.bashrc"     # Bash
fi

# 如果找到了配置文件
if [ -n "$SHELL_RC" ]; then
    # 检查别名是否已经存在（避免重复添加）
    # grep -q 静默搜索
    # 2>/dev/null 隐藏错误输出
    if ! grep -q "claude-stats" "$SHELL_RC" 2>/dev/null; then
        # 别名不存在，添加到配置文件
        echo "" >> "$SHELL_RC"
        echo "# Claude Code Monitor aliases" >> "$SHELL_RC"
        # 添加便捷命令别名
        echo "alias claude-stats='$APP_DIR/scripts/query.sh stats'" >> "$SHELL_RC"
        echo "alias claude-today='$APP_DIR/scripts/query.sh today'" >> "$SHELL_RC"
        echo "alias claude-msg='$APP_DIR/scripts/query.sh messages'" >> "$SHELL_RC"
        echo "alias claude-clean='$APP_DIR/scripts/query.sh clean'" >> "$SHELL_RC"
        echo "alias claude-flush-db='$APP_DIR/scripts/flush-db.sh'" >> "$SHELL_RC"
        echo "alias claude-query='$APP_DIR/scripts/query.sh'" >> "$SHELL_RC"
        echo -e "${GREEN}✓ Aliases added to $SHELL_RC${NC}"
    else
        # 别名已存在，跳过
        echo -e "${YELLOW}ℹ️  Aliases already exist in $SHELL_RC${NC}"
    fi
else
    # 未找到配置文件
    echo -e "${YELLOW}⚠️  Warning: Could not find .zshrc or .bashrc${NC}"
fi

# ============================================================
# 安装完成总结
# ============================================================
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Installation Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 显示后续操作步骤
echo -e "${BLUE}Next steps:${NC}"
echo ""
echo -e "  1. ${YELLOW}Restart Claude Code${NC} to activate hooks"
echo -e "     (Hooks have been automatically configured in ~/.claude/settings.json)"
echo ""
echo -e "  2. ${YELLOW}Restart your terminal${NC} or run:"
echo -e "     ${BLUE}source $SHELL_RC${NC}"
echo ""
echo -e "  3. ${YELLOW}Test the installation:${NC}"
echo -e "     ${BLUE}claude-stats${NC}      - View statistics"
echo -e "     ${BLUE}claude-today${NC}      - View today's sessions"
echo -e "     ${BLUE}claude-msg${NC}        - View message history"
echo -e "     ${BLUE}claude-clean 30${NC}   - Clean data older than 30 days"
echo -e "     ${BLUE}claude-flush-db${NC}   - Flush and recreate database"
echo -e "     ${BLUE}claude-query help${NC} - See all commands"
echo ""

# 显示安装位置信息
echo -e "${BLUE}Installation locations:${NC}"
echo -e "  App directory: $APP_DIR/"
echo -e "  Database: $CLAUDE_DIR/monitor.db"
echo -e "  Scripts: $APP_DIR/scripts/"
echo -e "  Logs: $APP_DIR/logs/"
echo -e "  Hooks config: $CLAUDE_SETTINGS"
if [ -f "$BACKUP_FILE" ]; then
    echo -e "  Settings backup: $BACKUP_FILE"
fi
echo ""

# 提示查看文档
echo -e "For more information, see: ${BLUE}README.md${NC}"
echo ""
