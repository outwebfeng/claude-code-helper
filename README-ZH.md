# Claude Code 监控系统

一个轻量级的 Claude Code 会话监控工具，自动追踪执行时间、记录对话历史，并在任务完成时提供桌面通知。

[English](README.md) | 简体中文

## ✨ 核心特性

- **📊 会话追踪**：自动追踪 Claude Code 会话的完整生命周期
- **💬 消息记录**：记录所有用户消息及其会话上下文
- **🔔 智能通知**：任务完成时弹出桌面通知，显示时长统计
- **📈 数据分析**：支持每日/每周统计和会话历史查询
- **🗄️ SQLite 数据库**：高效的本地存储，支持完整的 SQL 查询
- **🔍 强大查询**：丰富的命令行工具查看会话、消息和统计数据
- **🛡️ 安全卸载**：卸载前自动备份数据库
- **🎯 零侵入**：使用官方 Claude Code Hooks API

## 🎯 快速开始

### 安装

```bash
# 克隆仓库
git clone https://github.com/yourusername/claude-code-helper.git
cd claude-code-helper

# 运行安装脚本
./install.sh
```

安装程序会自动：
1. 复制脚本到 `~/.claude/claude-code-helper/`
2. 创建数据库 `~/.claude/monitor.db`
3. 自动配置 Claude Code hooks
4. 添加便捷的 shell 别名

### 首次使用

安装完成后：

1. **重启 Claude Code** 以激活 hooks
2. **重新加载 shell**：
   ```bash
   source ~/.zshrc  # 或 ~/.bashrc
   ```
3. **测试安装**：
   ```bash
   claude-stats  # 查看统计信息
   claude-today  # 查看今日会话
   ```

## 📖 使用指南

### 可用命令

```bash
# 查看今日会话
claude-today

# 查看统计信息
claude-stats

# 查看最近的消息（默认 20 条）
claude-msg

# 查看指定消息的详情
claude-msg <消息ID>

# 查看所有可用命令
claude-query help
```

### 查询示例

```bash
# 查看活跃会话
claude-query active

# 查看本周会话
claude-query week

# 导出数据为 CSV 格式
claude-query export csv

# 导出数据为 JSON 格式
claude-query export json

# 清理旧数据（超过 30 天）
claude-query clean 30
```

## 📊 数据库结构

系统使用 SQLite 数据库，包含以下结构：

### 数据表

- **sessions**：会话元数据（开始/结束时间、时长、状态、项目）
- **messages**：用户消息，关联到会话
- **events**：Hook 事件日志
- **statistics**：每日聚合统计数据

### 视图

- **active_sessions**：当前运行中的会话
- **today_stats**：今日实时统计

## 🗂️ 目录结构

```
~/.claude/
├── settings.json              # Claude Code 配置（共享）
├── monitor.db                 # SQLite 数据库
└── claude-code-helper/        # 应用目录（隔离）
    ├── scripts/               # 核心脚本
    ├── logs/                  # 日志文件
    └── backups/               # 手动备份
```

**设计优势**：
- ✅ 清晰隔离：所有应用文件在子目录中
- ✅ 安全卸载：删除应用目录不影响其他工具
- ✅ 数据库在主目录便于访问
- ✅ 卸载时自动备份（带时间戳）

## 🔄 卸载

```bash
./uninstall.sh
```

卸载程序会自动：
1. **备份数据库**到 `~/.claude/monitor.db.backup.时间戳`
2. 删除数据库文件
3. 删除应用目录
4. 清理 settings.json 中的 hooks 配置
5. 删除 shell 别名

**保留内容**：
- `~/.claude/` 目录（Claude Code 官方目录）
- 带时间戳的数据库备份
- 其他工具的数据

## 🛠️ 系统要求

- macOS 10.15+
- Bash 3.2+
- SQLite 3.x
- Claude Code（最新版本）
- Python 3.x（用于 hooks 配置）

### 可选依赖

- `terminal-notifier` 以获得更好的通知体验：
  ```bash
  brew install terminal-notifier
  ```

## 📋 输出示例

### 今日会话

```
=== 今日会话 ===
开始时间    耗时      状态        项目
--------  --------  ----------  --------------------
14:08     35秒      completed   claude-code-helper
13:45     2分15秒   completed   my-project
```

### 最近消息

```
=== 最近 20 条消息（含会话信息）===
ID  项目名称          会话开始        时长    状态       消息内容
--  ---------------  -------------  ------  ---------  --------------------------------
5   my-project       10-27 15:46    7m      completed  帮我优化数据库
4   my-project       10-27 15:46    7m      completed  显示当前的表结构
```

### 统计信息

```
=== 统计信息 ===
今日会话数：        5
今日完成数：        4
今日总时长：        1.5 小时
平均时长：          18 分钟
本周会话数：        23
```

## 🐛 故障排查

### Hooks 未触发

检查 hooks 配置：
```bash
cat ~/.claude/settings.json | python3 -m json.tool | grep -A 5 "hooks"
```

查看日志：
```bash
tail -f ~/.claude/claude-code-helper/logs/monitor.log
```

### 通知不显示

1. 检查 系统偏好设置 → 通知 → 终端
2. 安装 terminal-notifier：`brew install terminal-notifier`

### 数据库问题

```bash
# 检查数据库完整性
sqlite3 ~/.claude/monitor.db "PRAGMA integrity_check;"

# 查看表结构
sqlite3 ~/.claude/monitor.db ".tables"

# 手动备份
cp ~/.claude/monitor.db ~/.claude/backups/monitor.db.manual
```

## 🎨 命令详解

### claude-today
显示今日所有会话，包括开始时间、持续时长、状态和项目名称。

### claude-stats
显示统计信息，包括今日/本周会话数、总时长、平均时长等。

### claude-msg
显示最近的消息记录，包含会话上下文信息（项目、开始时间、时长、状态）。

参数：
- 无参数：显示最近 20 条消息
- `<消息ID>`：显示指定消息的完整详情

### claude-query
多功能查询工具，支持以下子命令：

- `active`：查看当前运行中的会话
- `week`：查看本周会话
- `export csv`：导出数据为 CSV 格式
- `export json`：导出数据为 JSON 格式
- `clean <天数>`：清理指定天数之前的数据
- `help`：显示帮助信息

## 🔒 隐私说明

本工具的所有数据都存储在您的本地计算机上（`~/.claude/monitor.db`），不会发送到任何外部服务器。

## 🤝 贡献

欢迎贡献！请随时提交 Pull Request。

## 📄 许可证

MIT License - 可自由用于个人或商业项目。

## 🙏 致谢

- 为 Anthropic 的 [Claude Code](https://claude.ai/code) 构建
- 使用官方 Claude Code Hooks API
- 灵感来源于更好的会话追踪和分析需求

## 💡 使用技巧

1. **定期备份数据库**：
   ```bash
   cp ~/.claude/monitor.db ~/.claude/backups/monitor.db.$(date +%Y%m%d)
   ```

2. **导出数据进行分析**：
   ```bash
   claude-query export csv
   # 使用 Excel 或其他工具分析导出的 CSV 文件
   ```

3. **查看详细日志**：
   ```bash
   tail -f ~/.claude/claude-code-helper/logs/monitor.log
   ```

4. **直接查询数据库**：
   ```bash
   sqlite3 ~/.claude/monitor.db
   # 使用 SQL 进行自定义查询
   ```

## 📞 支持

如果遇到问题或有功能建议，请在 GitHub 上提交 Issue。

---

**提示**：首次安装后，建议运行几次 Claude Code 会话以生成测试数据，然后使用各种查询命令熟悉功能。
