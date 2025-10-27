# Claude Code 监控系统

一个轻量级的本地监控工具，通过 Claude Hooks 机制和 SQLite 数据库，实现对 Claude Code 会话的全生命周期监控、数据记录和智能通知。

## 特性

- **零侵入**：基于官方 Hooks 机制，不修改 Claude Code 本体
- **轻量级**：使用 SQLite + Shell 脚本，资源占用极低
- **数据持久化**：完整记录会话历史，支持统计分析
- **智能通知**：任务完成自动提醒，提升工作效率
- **异常检测**：自动检测并清理异常会话
- **数据导出**：支持 CSV 和 JSON 格式导出

## 系统要求

- macOS 10.15+
- Bash 3.2+
- SQLite 3.x
- Claude Code (最新版本)

## 快速开始

### ⚠️ 调试模式 (首次使用推荐)

**如果你是首次安装或遇到 Hooks 不触发的问题,请先运行调试版本:**

```bash
# 1. 初始化调试环境
bash scripts/init.sh

# 2. 运行测试脚本
bash test_hooks_simple.sh

# 3. 查看调试日志
tail -f ~/.claude/logs/hook_debug.log
```

当前脚本已简化为**仅记录日志**,便于排查 Hooks 触发问题。

详细调试指南: [QUICK_DEBUG.md](QUICK_DEBUG.md) | [docs/DEBUG_GUIDE.md](docs/DEBUG_GUIDE.md)

---

### 正式安装

```bash
# 克隆或下载项目
cd claude-code-helper

# 运行安装脚本
bash install.sh

# 可选：安装守护进程（每5分钟自动清理异常会话）
bash install.sh --with-daemon
```

**注意**: 当前版本的脚本是调试简化版。如需完整功能,请从备份恢复:
```bash
cp backups/scripts_backup_*/\*.sh scripts/
```

### 配置 Claude Code Hooks

安装完成后，Hooks 已自动配置到 `~/.claude/settings.json`：

1. 安装脚本已自动将 Hooks 配置添加到 Claude Code 设置
2. 重启 Claude Code 以激活 Hooks
3. 如需手动查看配置，请参考 `~/.claude/settings.json`

详细配置说明请参考 [docs/INSTALL.md](docs/INSTALL.md)

## 项目结构

### 项目文件组织

```
claude-code-helper/
├── README.md                    # 项目说明文档（本文件）
├── CLAUDE.md                    # Claude Code 助手指南
├── install.sh                   # 安装脚本（自动配置）
├── uninstall.sh                 # 卸载脚本
├── test.sh                      # 测试脚本
├── com.claude.monitor.plist     # LaunchAgent 守护进程配置
├── docs/                        # 文档目录
│   ├── INSTALL.md              # 详细安装指南
│   ├── plan.md                 # 项目实施计划
│   ├── prd.md                  # 产品需求文档
│   └── PROJECT_SUMMARY.md      # 项目总结
└── scripts/                     # 核心脚本目录
    ├── init.sh                 # 数据库初始化脚本
    ├── record.sh               # 事件记录脚本（Hook 处理器）
    ├── cleanup.sh              # 异常会话清理脚本
    └── query.sh                # 数据查询工具
```

### 安装后的文件结构

安装后，系统文件会被部署到 `~/.claude/` 目录：

```
~/.claude/
├── settings.json                     # Claude Code 官方配置文件（仅修改 hooks 字段）
└── claude-code-helper/              # 应用专属目录（隔离设计，可安全删除）
    ├── monitor.db                   # SQLite 数据库（会话数据）
    ├── scripts/                     # 脚本目录（从项目复制）
    │   ├── init.sh                 # 数据库初始化
    │   ├── record.sh               # 事件记录（SessionStart, Stop, Notification）
    │   └── query.sh                # 查询工具（today, stats, export 等）
    ├── logs/                        # 日志目录
    │   ├── monitor.log             # 运行日志
    │   ├── daemon.log              # 守护进程日志（可选）
    │   └── daemon_error.log        # 守护进程错误日志（可选）
    └── backups/                     # 数据库备份目录
```

**设计优势**：
- ✅ **清晰隔离**：所有应用文件都在 `claude-code-helper/` 子目录中
- ✅ **安全卸载**：删除应用目录即可完全清理，不影响其他工具
- ✅ **无冲突**：与其他可能使用 `~/.claude` 的工具完全隔离
- ✅ **易维护**：文件组织清晰，所有权明确

### 核心文件说明

#### 安装与配置

- **install.sh**: 主安装脚本
  - 检查系统依赖（sqlite3, osascript）
  - 初始化数据库结构
  - 自动配置 Claude Code Hooks 到 `~/.claude/settings.json`
  - 设置脚本权限
  - 添加命令别名到 shell 配置
  - 可选安装守护进程（`--with-daemon` 参数）

- **uninstall.sh**: 卸载脚本（安全设计，采用目录隔离策略）
  - 停止并移除 LaunchAgent 守护进程
  - 智能移除 Hooks 配置（仅删除本项目添加的 hooks，保留其他配置）
  - ⚠️ **目录隔离设计**：
    - **删除**: `~/.claude/claude-code-helper/` 整个目录（我们的专属空间）
    - **保留**: `~/.claude/` 目录和 `settings.json` 文件（共享资源）
    - **优势**: 一条命令即可完全清理，不影响其他工具
  - 询问是否保留数据（y=保留数据库和日志，n=完全删除）
  - 清理 shell 别名
  - 创建 settings.json 备份（带时间戳，安全回退）

#### 核心功能脚本

- **scripts/init.sh**: 数据库初始化
  - 创建目录结构（scripts, logs, backups）
  - 创建 4 张表：sessions, messages, events, statistics
  - 创建 5 个索引：优化查询性能
  - 创建 1 个触发器：自动更新 updated_at
  - 创建 2 个视图：active_sessions, today_stats

- **scripts/record.sh**: 事件记录处理器
  - 处理 SessionStart 事件：创建会话、记录消息
  - 处理 Stop 事件：更新时长、发送通知、更新统计
  - 处理 Notification 事件：提醒用户输入
  - SQL 注入防护：转义特殊字符

- **scripts/cleanup.sh**: 异常清理
  - 检测并清理异常终止的会话（使用 `kill -0` 检测进程）
  - 清理超时会话（>24小时）
  - 执行数据库维护（VACUUM）

- **scripts/query.sh**: 数据查询工具
  - `today`: 显示今日会话列表
  - `stats`: 显示统计信息（今日、本周）
  - `active`: 显示活跃会话
  - `messages`: 查看消息记录
  - `export csv/json`: 导出数据
  - `clean [days]`: 清理历史数据
  - `help`: 显示帮助信息

#### 守护进程

- **com.claude.monitor.plist**: LaunchAgent 配置
  - 每 5 分钟自动执行 cleanup.sh
  - 开机自启动（RunAtLoad: true）
  - 日志输出到 ~/.claude/logs/daemon.log

#### 测试

- **test.sh**: 自动化测试脚本
  - 数据库连接测试
  - 表结构、索引、视图测试
  - 会话创建、更新、终止测试
  - 消息插入、特殊字符转义测试
  - 查询功能测试

#### 文档

- **CLAUDE.md**: Claude Code 助手专用文档
  - 项目架构说明
  - 开发命令参考
  - 实施指南
  - 技术决策说明

- **docs/INSTALL.md**: 详细安装指南
  - 系统要求检查
  - 分步安装说明
  - Hooks 配置详解
  - 故障排查指南

- **docs/plan.md**: 项目实施计划
  - 6 个阶段的详细计划
  - 任务清单和验收标准
  - 技术要点总结
  - 风险与对策

- **docs/prd.md**: 产品需求文档
  - 功能需求
  - 技术架构
  - 数据模型
  - 接口定义

## 使用方法

### 命令行工具

安装后会自动添加以下命令别名：

```bash
# 查看统计信息
claude-stats

# 查看今日会话列表
claude-today

# 运行清理脚本
claude-clean

# 使用查询工具
claude-query <command>
```

### 查询命令

```bash
# 显示今日会话列表
claude-query today

# 显示统计信息（今日、本周）
claude-query stats

# 显示活跃会话（正在运行的会话）
claude-query active

# 显示消息记录
claude-query messages          # 最近10条消息
claude-query messages 5        # 会话ID为5的所有消息

# 导出数据
claude-query export csv        # 导出为CSV格式
claude-query export json       # 导出为JSON格式

# 清理历史数据
claude-query clean             # 清理30天前的数据（默认）
claude-query clean 90          # 清理90天前的数据

# 显示帮助信息
claude-query help
```

## 功能说明

### 会话记录

系统会自动记录每次 Claude Code 会话的以下信息：

- 开始/结束时间
- 执行时长（自动计算）
- 用户发送的消息
- 项目名称和路径
- 会话状态（running/completed/terminated）

### 智能通知

**会话完成通知**：
- 显示项目名称
- 显示本次执行时长
- 显示今日统计（第N次，平均耗时）

**需要输入通知**：
- 当 Claude Code 需要用户输入时
- 自动激活终端窗口
- 播放提示音

### 异常处理

系统能够检测并处理以下异常情况：

- 正常退出（Stop 事件）
- 强制退出（Ctrl+C）
- 终端关闭
- 系统关机/重启
- 网络中断

异常会话会被自动标记为 `terminated` 状态，并记录异常类型。

### 数据查询

提供多种查询功能：

1. **今日会话**：查看今天的所有会话
2. **统计分析**：总时长、平均时长、项目分布
3. **活跃会话**：当前正在运行的会话
4. **消息记录**：查看用户发送的历史消息
5. **数据导出**：导出为 CSV 或 JSON 格式

## 守护进程

可选安装 LaunchAgent 守护进程：

```bash
bash install.sh --with-daemon
```

守护进程会每 5 分钟自动执行以下任务：

- 检测并清理异常会话（进程已终止）
- 清理超时会话（运行超过 24 小时）
- 执行数据库维护（VACUUM）

### 管理守护进程

```bash
# 停止守护进程
launchctl unload ~/Library/LaunchAgents/com.claude.monitor.plist

# 启动守护进程
launchctl load ~/Library/LaunchAgents/com.claude.monitor.plist

# 查看守护进程状态
launchctl list | grep claude.monitor

# 查看守护进程日志
tail -f ~/.claude/logs/daemon.log
```

## 示例输出

### 统计信息

```
=== 统计信息 ===
metric = 今日会话
 value = 5

metric = 今日完成
 value = 4

metric = 今日总时长(小时)
 value = 2.5

metric = 平均时长(分钟)
 value = 30.0
```

### 今日会话

```
=== 今日会话 ===
开始时间  耗时         状态        项目
--------  ----------  ----------  ----------
14:30     25m30s      completed   my-project
13:15     18m45s      completed   test-app
11:00     1h5m        completed   website
```

## 卸载

```bash
bash uninstall.sh
```

卸载脚本会：

1. 停止并移除 LaunchAgent 守护进程
2. 从 `settings.json` 中移除 Hooks 配置（保留文件本身和其他配置）
3. 询问是否保留数据：
   - 选择 **n**（不保留）：删除整个 `~/.claude/claude-code-helper/` 目录
   - 选择 **y**（保留）：只删除 `scripts/`，保留数据库和日志
4. 清理 shell 配置中的别名
5. 创建带时间戳的备份文件（`settings.json.backup.20250127_143022`）

⚠️ **安全保证**（采用目录隔离设计）：
- ✅ **完全隔离**：应用数据都在 `~/.claude/claude-code-helper/` 子目录
- ✅ **安全删除**：卸载只需删除这一个目录，不影响其他工具
- ✅ **保护共享文件**：`~/.claude/` 和 `settings.json` 永远不会被删除
- ✅ **智能备份**：修改 settings.json 前自动创建带时间戳的备份

## 故障排查

### 通知不显示

确认 macOS 通知权限已启用：

1. 系统偏好设置 → 通知
2. 找到"终端"或"iTerm2"
3. 确保"允许通知"已启用

### 数据库错误

如果遇到数据库错误，可以尝试：

```bash
# 备份数据库
cp ~/.claude/claude-code-helper/monitor.db ~/.claude/claude-code-helper/backups/monitor.db.backup

# 重新初始化
bash ~/.claude/claude-code-helper/scripts/init.sh

# 如果需要，导出数据后删除数据库重建
claude-query export csv
rm ~/.claude/claude-code-helper/monitor.db
bash ~/.claude/claude-code-helper/scripts/init.sh
```

### Hook 不工作

1. 确认 Hooks 配置正确添加到 Claude Code
2. 检查脚本权限：`ls -l ~/.claude/scripts/*.sh`
3. 查看日志：`tail -f ~/.claude/logs/monitor.log`
4. 手动测试：`bash ~/.claude/scripts/record.sh start "test"`

## 常见问题

**Q: 数据会占用多少空间？**

A: 一年的数据大约 < 10MB（假设每天 10 个会话）

**Q: 可以在多台设备上使用吗？**

A: 目前只支持本地存储，每台设备独立。云端同步功能计划在 v1.2 版本实现。

**Q: 会影响 Claude Code 性能吗？**

A: 不会。Hook 执行时间 < 50ms，数据库查询 < 10ms，对性能影响可忽略不计。

**Q: 如何备份数据？**

A: 使用导出功能：`claude-query export csv` 或直接复制数据库文件 `~/.claude/monitor.db`

**Q: 支持 Linux/Windows 吗？**

A: 当前版本仅支持 macOS。Linux 支持计划在 v1.1 版本实现，Windows 支持在 v1.2。

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可证

MIT License

## 更新日志

### v1.0 (2025-01)
- 初始版本
- 基础会话记录功能
- macOS 通知支持
- 数据查询和导出
- 异常检测和清理
- LaunchAgent 守护进程

## 联系方式

如有问题或建议，请提交 Issue。

---

**享受使用 Claude Code 监控系统！** 🚀
