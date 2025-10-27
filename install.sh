#!/bin/bash
# install.sh
# Claude Code Monitor - 安装脚本
#
# 功能：自动安装 Claude Code 监控系统的所有组件
# 用法：bash install.sh [--with-daemon]
#
# 安装内容：
#   1. 复制脚本文件到 ~/.claude/scripts/
#   2. 初始化数据库结构
#   3. 配置 Claude Code Hooks（自动修改 settings.json）
#   4. 添加命令别名到 shell 配置
#   5. 可选：安装守护进程（定时清理）

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

# 是否安装守护进程（默认不安装）
INSTALL_WITH_DAEMON=false

# ============================================================
# 终端颜色定义（用于美化输出）
# ============================================================
RED='\033[0;31m'      # 红色（错误）
GREEN='\033[0;32m'    # 绿色（成功）
BLUE='\033[0;34m'     # 蓝色（信息）
YELLOW='\033[1;33m'   # 黄色（警告）
NC='\033[0m'          # 无颜色（重置）

# ============================================================
# 解析命令行参数
# ============================================================
# 如果传入 --with-daemon 参数，则安装守护进程
if [ "$1" = "--with-daemon" ]; then
    INSTALL_WITH_DAEMON=true
fi

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

# 检查 osascript 是否存在（可选，用于 macOS 通知）
# 不存在只警告，不影响安装
if ! command -v osascript &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: osascript not found (macOS notifications will not work)${NC}"
else
    echo -e "${GREEN}✓ osascript found${NC}"
fi

# 检查 terminal-notifier 是否安装（推荐，用于更可靠的通知）
if ! command -v terminal-notifier &> /dev/null; then
    echo -e "${YELLOW}⚠️  Warning: terminal-notifier not found${NC}"
    echo -e "${YELLOW}   terminal-notifier provides more reliable notifications than osascript${NC}"
    echo -e "${YELLOW}   Would you like to install it? (y/n)${NC}"
    read -p "   Install terminal-notifier via homebrew? (y/n): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if command -v brew &> /dev/null; then
            echo -e "${YELLOW}   Installing terminal-notifier...${NC}"
            brew install terminal-notifier
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ terminal-notifier installed${NC}"
            else
                echo -e "${YELLOW}⚠️  Failed to install terminal-notifier, will use osascript instead${NC}"
            fi
        else
            echo -e "${YELLOW}⚠️  Homebrew not found, cannot install terminal-notifier${NC}"
            echo -e "${YELLOW}   You can install it later with: brew install terminal-notifier${NC}"
        fi
    else
        echo -e "${YELLOW}   Skipping terminal-notifier installation${NC}"
        echo -e "${YELLOW}   You can install it later with: brew install terminal-notifier${NC}"
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
# 步骤 6: 安装 LaunchAgent 守护进程（可选）
# ============================================================
# 只有传入 --with-daemon 参数时才执行
if [ "$INSTALL_WITH_DAEMON" = true ]; then
    echo ""
    echo -e "${YELLOW}Installing LaunchAgent daemon...${NC}"

    # plist 模板文件路径（项目目录）
    PLIST_TEMPLATE="$SCRIPT_DIR/com.claude.monitor.plist"
    # plist 目标路径（LaunchAgent 自动加载目录）
    PLIST_DEST="$HOME/Library/LaunchAgents/com.claude.monitor.plist"

    if [ -f "$PLIST_TEMPLATE" ]; then
        # 使用 sed 替换模板中的 YOUR_USERNAME 为实际的 HOME 路径
        # s|查找|替换|g 是 sed 的替换语法
        # |g 表示全局替换
        sed "s|/Users/YOUR_USERNAME|$HOME|g" "$PLIST_TEMPLATE" > "$PLIST_DEST"

        # 先尝试卸载旧的（如果存在）
        # 2>/dev/null 隐藏错误输出
        # || true 即使失败也继续执行
        launchctl unload "$PLIST_DEST" 2>/dev/null || true

        # 加载 LaunchAgent（立即启动守护进程）
        launchctl load "$PLIST_DEST"

        echo -e "${GREEN}✓ LaunchAgent installed and loaded${NC}"
        echo -e "${GREEN}  Cleanup will run every 5 minutes${NC}"
    else
        echo -e "${YELLOW}⚠️  Warning: plist template not found${NC}"
    fi
fi

# ============================================================
# 步骤 7: 配置 Claude Code Hooks（核心步骤）
# ============================================================
echo ""
echo -e "${YELLOW}Configuring Claude Code Hooks...${NC}"

# Claude Code 的配置文件路径
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

# 检查配置文件是否存在
if [ -f "$CLAUDE_SETTINGS" ]; then
    # 备份现有配置（安全措施，带时间戳）
    BACKUP_FILE="${CLAUDE_SETTINGS}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CLAUDE_SETTINGS" "$BACKUP_FILE"
    echo -e "${BLUE}  Backed up existing settings to $BACKUP_FILE${NC}"

    # 检查是否已经配置过 hooks
    # grep -q 静默搜索（不输出结果）
    # 如果找到 "hooks" 字符串，返回 0（真）
    if grep -q '"hooks"' "$CLAUDE_SETTINGS" 2>/dev/null; then
        # 已存在 hooks 配置，警告用户手动合并
        echo -e "${YELLOW}⚠️  Warning: Hooks configuration already exists in settings.json${NC}"
        echo -e "${YELLOW}  Please manually check if hooks are configured correctly${NC}"
    else
        # 没有 hooks 配置，使用 Python 自动添加
        # ============================================================
        # Python 脚本：智能合并 hooks 配置
        # ============================================================
        # << 'EOF' 是 Here Document 语法，将多行文本传递给 python3
        # 使用 'EOF' (带引号) 防止 shell 变量展开
        # 通过环境变量传递参数
        SETTINGS_FILE="$CLAUDE_SETTINGS" APP_DIR="$APP_DIR" python3 << 'EOF'
import json
import sys
import os

# 从环境变量获取文件路径
settings_file = os.environ['SETTINGS_FILE']  # ~/.claude/settings.json
app_dir = os.environ['APP_DIR']              # ~/.claude/claude-code-helper

# 读取现有的 settings.json 内容
with open(settings_file, 'r') as f:
    settings = json.load(f)

# 添加 hooks 配置
# hooks 结构：事件类型 → hook 配置列表 → 具体的 hook
# 注意：SessionStart 需要 matcher (startup/resume/clear/compact)
# Stop 和 Notification 不需要 matcher
settings['hooks'] = {
    # SessionStart 事件：会话开始或恢复时触发
    "SessionStart": [
        {
            "matcher": "startup",
            "hooks": [{
                "type": "command",
                "command": f"{app_dir}/scripts/record.sh start"
            }]
        },
        {
            "matcher": "resume",
            "hooks": [{
                "type": "command",
                "command": f"{app_dir}/scripts/record.sh start"
            }]
        }
    ],
    # UserPromptSubmit 事件：用户提交消息时触发（用于记录提问时间）
    "UserPromptSubmit": [{
        "hooks": [{
            "type": "command",
            "command": f"{app_dir}/scripts/record.sh user_prompt"
        }]
    }],
    # Stop 事件：会话结束时触发
    "Stop": [{
        "hooks": [{
            "type": "command",
            "command": f"{app_dir}/scripts/record.sh stop"
        }]
    }],
    # Notification 事件：需要用户输入时触发
    "Notification": [{
        "hooks": [{
            "type": "command",
            "command": f"{app_dir}/scripts/record.sh notification"
        }]
    }]
}

# 将修改后的配置写回文件
# indent=2 使 JSON 格式化输出（美观易读）
with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')  # 末尾添加换行符

print("✓ Hooks configured")
EOF
        # 检查 Python 脚本是否执行成功
        # $? 是上一个命令的退出状态（0=成功，非0=失败）
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Claude Code Hooks configured in $CLAUDE_SETTINGS${NC}"
        else
            # Python 不可用或执行失败，降级到手动配置
            echo -e "${YELLOW}⚠️  Python not available, please manually configure hooks${NC}"
            echo -e "${YELLOW}  Please manually add hooks to: $CLAUDE_SETTINGS${NC}"
            echo -e "${YELLOW}  See docs/INSTALL.md for hook configuration details${NC}"
        fi
    fi
else
    # settings.json 文件不存在，自动创建
    echo -e "${YELLOW}ℹ️  Claude settings file not found, creating new one...${NC}"

    # 创建基本的 settings.json 文件并添加 hooks 配置
    SETTINGS_FILE="$CLAUDE_SETTINGS" APP_DIR="$APP_DIR" python3 << 'EOF'
import json
import sys
import os

settings_file = os.environ['SETTINGS_FILE']
app_dir = os.environ['APP_DIR']

# 创建基本的 settings 结构
settings = {
    "hooks": {
        "SessionStart": [
            {
                "matcher": "startup",
                "hooks": [{
                    "type": "command",
                    "command": f"{app_dir}/scripts/record.sh start"
                }]
            },
            {
                "matcher": "resume",
                "hooks": [{
                    "type": "command",
                    "command": f"{app_dir}/scripts/record.sh start"
                }]
            }
        ],
        "UserPromptSubmit": [{
            "hooks": [{
                "type": "command",
                "command": f"{app_dir}/scripts/record.sh user_prompt"
            }]
        }],
        "Stop": [{
            "hooks": [{
                "type": "command",
                "command": f"{app_dir}/scripts/record.sh stop"
            }]
        }],
        "Notification": [{
            "hooks": [{
                "type": "command",
                "command": f"{app_dir}/scripts/record.sh notification"
            }]
        }]
    }
}

# 写入新的配置文件
with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')

print("✓ Created new settings.json with hooks configuration")
EOF
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Claude Code Hooks configured in new $CLAUDE_SETTINGS${NC}"
    else
        echo -e "${YELLOW}⚠️  Failed to create settings file${NC}"
        echo -e "${YELLOW}  Please manually create: $CLAUDE_SETTINGS${NC}"
        echo -e "${YELLOW}  See docs/INSTALL.md for hook configuration details${NC}"
    fi
fi

# ============================================================
# 步骤 8: 添加 Shell 命令别名
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
        echo "alias claude-clean='$APP_DIR/scripts/cleanup.sh'" >> "$SHELL_RC"
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
echo -e "     ${BLUE}claude-stats${NC}  - View statistics"
echo -e "     ${BLUE}claude-today${NC}  - View today's sessions"
echo -e "     ${BLUE}claude-query help${NC}  - See all commands"
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

# 如果安装了守护进程，显示相关信息
if [ "$INSTALL_WITH_DAEMON" = true ]; then
    echo -e "${GREEN}🔄 Daemon installed:${NC} Cleanup runs every 5 minutes"
    echo ""
fi

# 提示查看文档
echo -e "For more information, see: ${BLUE}README.md${NC}"
echo ""
