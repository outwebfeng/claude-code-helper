# Claude Code 监控系统实现计划
**版本**: v1.0
**创建时间**: 2025-10-25
**基于**: prd.md v1.0
**更新**: 2025-10-25 - 配置文件从 config.json 改为 settings.json

---

## 重要说明

**配置文件位置变更**：本计划原始版本中提到的 `~/.claude/config.json` 已更改为 `~/.claude/settings.json`。这是 Claude Code 的实际配置文件位置。install.sh 脚本会自动将 Hooks 配置写入 settings.json，无需手动创建 config.json。

**当前实现状态**（2025-10-27更新）：
- ✅ init.sh: 已简化为仅创建目录和日志（数据库初始化待实现）
- ✅ record.sh: 已实现，支持 SessionStart/Stop/UserPromptSubmit/SessionEnd 事件
- ❌ cleanup.sh: 待实现
- ✅ query.sh: 已实现
- ✅ install.sh: 已实现，使用 Python 自动配置 Hooks
- ✅ 通知系统: 使用 terminal-notifier 替代 osascript

---

## 项目概述

本项目旨在开发一个轻量级的 Claude Code 监控系统，通过 Claude Hooks 机制和 SQLite 数据库，实现对 Claude Code 会话的全生命周期监控、数据记录和智能通知。

**核心特性**：
- 零侵入式监控（基于官方 Hooks）
- 完整会话记录（时间、消息、项目信息）
- 智能通知系统（完成提醒、统计信息）
- 异常检测与自动清理
- 数据查询与导出

---

## 实施阶段

### Phase 1: 基础设施搭建 (第1-2天)

#### 1.1 数据库层实现

**任务**: 创建 `scripts/init.sh` 初始化脚本

**详细内容**:
- [ ] 创建目录结构 (`~/.claude/scripts`, `logs`, `backups`)
- [ ] 实现数据库表结构
  - [ ] `sessions` 表：会话核心数据
    - 字段：id, session_uuid, start_time, end_time, duration, status, project_name, project_path, pid, terminal_session, created_at, updated_at
    - CHECK 约束：status IN ('running', 'completed', 'terminated')
  - [ ] `messages` 表：用户消息记录
    - 字段：id, session_id, message_type, content, timestamp
    - 外键：session_id → sessions(id) ON DELETE CASCADE
  - [ ] `events` 表：事件日志
    - 字段：id, session_id, event_type, event_data (JSON), timestamp
    - 外键：session_id → sessions(id) ON DELETE CASCADE
  - [ ] `statistics` 表：每日统计汇总
    - 字段：id, date, total_sessions, total_duration, avg_duration, completed_count, terminated_count, updated_at
    - UNIQUE 约束：date

- [ ] 创建数据库索引
  - `idx_sessions_status_time`: (status, start_time)
  - `idx_sessions_project`: (project_name)
  - `idx_messages_session`: (session_id)
  - `idx_events_session_type`: (session_id, event_type)
  - `idx_statistics_date`: (date)

- [ ] 创建触发器
  - `update_sessions_timestamp`: 自动更新 sessions.updated_at

- [ ] 创建视图
  - `active_sessions`: 筛选 status='running' 的会话
  - `today_stats`: 今日统计（总会话数、完成数、异常数、平均时长、总时长）

- [ ] 生成 Hooks 配置文件 (`~/.claude/config.json`)
  - SessionStart → `~/.claude/scripts/record.sh start`
  - Stop → `~/.claude/scripts/record.sh stop`
  - Notification → `~/.claude/scripts/record.sh notification`

**验收标准**:
- 运行 `init.sh` 后，数据库文件创建成功
- 4张表、5个索引、1个触发器、2个视图创建成功
- config.json 格式正确

---

#### 1.2 项目结构搭建

**任务**: 创建项目文件结构和配置文件

**详细内容**:
- [x] 创建 `com.claude.monitor.plist` (LaunchAgent 配置)
  - Label: com.claude.monitor
  - ProgramArguments: `/bin/bash ~/.claude/scripts/cleanup.sh`
  - StartInterval: 300 (每5分钟)
  - RunAtLoad: true
  - StandardOutPath/ErrorPath: 日志路径

- [x] 创建 `install.sh` 主安装脚本框架 **（已完成，包含自动 Hooks 配置）**
  - 检查依赖 (sqlite3, osascript, terminal-notifier)
  - 调用 init.sh
  - 设置脚本权限
  - **使用 Python 自动配置 Hooks 到 ~/.claude/settings.json**
  - 支持 SessionStart (startup/resume matcher)
  - 可选参数 `--with-daemon` 安装守护进程
  - 添加 shell 别名到 ~/.zshrc 或 ~/.bashrc

**验收标准**:
- plist 文件格式符合 macOS LaunchAgent 规范
- install.sh 可执行且逻辑完整

---

### Phase 2: 核心功能开发 (第3-5天)

#### 2.1 事件记录脚本 (record.sh)

**任务**: 实现核心事件记录逻辑

**详细内容**:

**2.1.1 辅助函数**
- [ ] `log()`: 统一日志记录函数
  - 格式: `[YYYY-MM-DD HH:MM:SS] message`
  - 输出到: `~/.claude/logs/monitor.log`

- [ ] `generate_uuid()`: 生成唯一会话标识
  - 算法: `$(date +%s)-$$-$RANDOM`
  - 确保唯一性

- [ ] `get_project_info()`: 获取项目信息
  - 项目路径: `$PWD`
  - 项目名称: `basename "$PWD"`
  - 返回格式: `name|path`

- [ ] `get_terminal_session()`: 获取终端会话标识
  - macOS: `$TERM_SESSION_ID`
  - 用于区分不同终端窗口

- [ ] `get_or_create_session()`: 获取或创建当前会话
  - 查找最新的 running 会话
  - 不存在则创建新会话
  - 返回 session_id

- [ ] `record_message()`: 记录用户消息
  - SQL 注入防护：转义单引号 `'` → `''`
  - 插入 messages 表

- [ ] `record_event()`: 记录事件
  - 支持 JSON 格式的 event_data
  - 插入 events 表

**2.1.2 事件处理器**
- [x] **SessionStart 处理** **（已完成）**
  - 调用 `get_or_create_session()`
  - 记录 SessionStart 事件（包含 source 类型）
  - 支持 startup 和 resume 两种启动方式
  - 发送启动通知
  - 记录日志

- [x] **UserPromptSubmit 处理** **（新增）**
  - 获取当前会话 ID
  - 记录用户消息到 messages 表
  - 记录 UserPromptSubmit 事件
  - **更新 last_prompt_time 字段**（用于精确计算单次对话耗时）
  - 记录日志

- [x] **Stop 处理** **（已完成，使用 last_prompt_time）**
  - 获取当前会话 ID
  - **从 last_prompt_time 计算单次对话耗时**（而非从 start_time）
  - 更新会话状态：
    - end_time = datetime('now')
    - duration = 计算总时长（从 start_time）
    - status = 'completed'
  - 记录 Stop 事件
  - 查询统计信息（本次时长、项目名、今日统计）
  - 格式化时长显示
  - **使用 terminal-notifier 发送通知**
  - 更新 statistics 表（INSERT OR REPLACE）

- [x] **SessionEnd 处理** **（新增）**
  - 获取当前会话 ID
  - 检查是否有 last_prompt_time
  - 如果有：计算耗时并发送完成通知
  - 如果没有：静默标记会话结束，不发送通知
  - 记录 SessionEnd 事件

- [x] **Error 处理** **（已完成）**
  - 获取当前会话 ID
  - 记录 Error 事件
  - 更新会话状态为 'terminated'
  - 计算并保存时长
  - 发送错误通知

**验收标准**:
- 4种事件处理器功能完整
- SQL 转义正确处理特殊字符
- 日志记录清晰可追溯
- 错误处理健壮（set -euo pipefail）

---

#### 2.2 通知系统实现

**任务**: 实现 macOS 通知功能

**详细内容**:
- [x] **Stop/SessionEnd 事件通知** **（已完成，使用 terminal-notifier）**
  - 标题: "✅ Claude Code 完成"
  - 内容格式:
    ```
    项目: {project_name}
    耗时: {formatted_duration}（基于 last_prompt_time）
    今日: 第{count}次, 平均{avg_duration}
    ```
  - **使用 terminal-notifier**（推荐）或回退到 osascript
  - 播放声音: "Glass"
  - 后台执行（使用 &）

- [x] **SessionStart 事件通知** **（新增）**
  - 标题: "🚀 Claude Code 启动"
  - 内容: "项目: {project_name}"
  - 播放声音: "Blow"

- [x] **Error 事件通知** **（新增）**
  - 标题: "❌ Claude Code 错误"
  - 内容: 错误消息
  - 播放声音: "Funk"

- [x] **时长格式化函数** **（已完成）**
  - < 60秒: "X秒"
  - < 3600秒: "X分Y秒"
  - >= 3600秒: "X小时Y分"

**验收标准**:
- ✅ 通知在 macOS 通知中心正确显示
- ✅ 时长格式化准确
- ✅ 使用 terminal-notifier 时更可靠
- ✅ 如果 terminal-notifier 不可用会记录警告日志

---

#### 2.3 异常清理脚本 (cleanup.sh)

**任务**: 实现异常会话检测与清理

**当前状态**: ❌ **待实现**（scripts/cleanup.sh 文件不存在）

**详细内容**:
- [ ] `cleanup_abnormal_sessions()`: 清理异常会话
  - 查询所有 status='running' 的会话
  - 使用 `kill -0 $pid` 检测进程是否存在
  - 进程不存在则：
    - 更新状态为 'terminated'
    - 计算并保存时长
    - 记录 AbnormalTermination 事件
  - 日志记录每个清理操作

- [ ] `cleanup_timeout_sessions()`: 清理超时会话
  - 查找 running 状态且开始时间 > 24小时的会话
  - 标记为 'terminated'
  - 记录日志

- [ ] `main()`: 主函数
  - 执行异常会话清理
  - 执行超时会话清理
  - 执行数据库维护 (VACUUM)
  - 记录开始/完成日志

**验收标准**:
- 能正确检测已终止的进程
- 超时会话（>24h）被自动清理
- VACUUM 执行后数据库文件大小优化
- 日志记录详细

**注意**: 当前该脚本缺失，LaunchAgent 守护进程无法正常工作

---

### Phase 3: 查询工具开发 (第6-7天)

#### 3.1 查询脚本 (query.sh)

**任务**: 实现数据查询与导出功能

**详细内容**:

- [ ] **today 命令**: 显示今日会话列表
  - 字段：开始时间(HH:MM)、耗时、状态、项目名
  - 耗时格式化：<60s显示秒，<3600显示分秒，否则显示小时分钟
  - 列宽设置：.width 8 20 10 10 30
  - 按开始时间降序排序

- [ ] **stats 命令**: 显示统计信息
  - 今日会话数
  - 今日完成数
  - 今日总时长（小时，保留2位小数）
  - 平均时长（分钟，保留1位小数）
  - 本周总会话数
  - 本周总时长（小时）
  - 使用 `.mode line` 格式化输出

- [ ] **active 命令**: 显示活跃会话
  - 字段：id, 开始时间, 项目名, 已运行时长（秒）
  - 实时计算已运行时长
  - 按开始时间降序排序

- [ ] **messages 命令**: 显示消息记录
  - 无参数：显示最近10条消息（所有会话）
  - 带 session_id：显示特定会话的所有消息
  - 字段：时间、消息内容（截断处理）

- [ ] **export 命令**: 导出数据
  - CSV 格式：使用 sqlite3 -csv 模式
  - JSON 格式：使用 json_group_array + json_object
  - 输出文件名：`~/claude_export_YYYYMMDD_HHMMSS.{csv|json}`
  - 导出字段：session_uuid, start_time, end_time, duration, status, project_name, project_path

- [ ] **clean 命令**: 清理历史数据
  - 参数：天数（默认30天）
  - 删除超过指定天数的 sessions
  - 级联删除关联的 messages 和 events
  - 执行 VACUUM
  - 显示删除数量

- [ ] **help 命令**: 帮助信息
  - 列出所有可用命令
  - 每个命令的参数说明

**3.1.2 彩色输出**
- [ ] 定义颜色常量（RED, GREEN, BLUE, YELLOW, NC）
- [ ] 为不同命令输出使用不同颜色
- [ ] 成功消息：绿色
- [ ] 警告消息：黄色
- [ ] 错误消息：红色
- [ ] 标题：蓝色

**验收标准**:
- 7个命令全部功能正常
- 输出格式美观、易读
- CSV/JSON 导出格式正确
- 彩色输出在终端正确显示

---

### Phase 4: 守护进程与安装 (第8天)

#### 4.1 LaunchAgent 完善

**任务**: 完成守护进程配置

**详细内容**:
- [ ] 验证 plist 文件格式
- [ ] 测试 launchctl load/unload
- [ ] 验证定时执行（每5分钟）
- [ ] 验证日志输出到指定路径
- [ ] 测试开机自启动（RunAtLoad）

**验收标准**:
- launchctl load 无错误
- cleanup.sh 每5分钟自动执行
- 日志正常写入 daemon.log

---

#### 4.2 安装脚本完善

**任务**: 完成 install.sh 实现

**详细内容**:
- [ ] 依赖检查
  - 检查 sqlite3 是否安装
  - 检查 osascript 是否可用（macOS）
  - 检查 ~/.zshrc 是否存在

- [ ] 安装流程
  - 显示欢迎信息
  - 执行 init.sh 初始化数据库
  - 设置所有脚本为可执行（chmod +x）
  - 如果带 `--with-daemon` 参数：
    - 复制 plist 到 ~/Library/LaunchAgents/
    - 执行 launchctl load
  - 添加 shell 别名到 ~/.zshrc

- [ ] 添加的别名
  ```bash
  alias claude-stats='~/.claude/scripts/query.sh stats'
  alias claude-today='~/.claude/scripts/query.sh today'
  alias claude-clean='~/.claude/scripts/cleanup.sh'
  ```

- [ ] 安装后提示
  - 显示安装成功信息
  - 提示用户手动配置 Claude Code Hooks
  - 提示重启终端或 source ~/.zshrc
  - 显示使用示例

**验收标准**:
- 安装过程无错误
- 所有脚本权限正确
- 别名添加成功
- 守护进程（可选）正常运行

---

#### 4.3 卸载脚本

**任务**: 创建 uninstall.sh

**详细内容**:
- [ ] 停止并卸载 LaunchAgent
  ```bash
  launchctl unload ~/Library/LaunchAgents/com.claude.monitor.plist
  rm ~/Library/LaunchAgents/com.claude.monitor.plist
  ```

- [ ] 询问是否保留数据
  - 保留：仅删除脚本和配置
  - 不保留：删除整个 ~/.claude 目录

- [ ] 从 ~/.zshrc 移除别名
  - 使用 sed 或 grep -v 删除相关行

- [ ] 显示卸载完成信息

**验收标准**:
- 守护进程完全停止
- 脚本和配置文件删除
- 别名从 shell 配置中移除
- 可选保留数据库文件

---

### Phase 5: 测试验证 (第9-10天)

#### 5.1 单元测试

**任务**: 创建 test.sh 测试脚本

**详细内容**:
- [ ] 测试框架搭建
  - `assert_equal()`: 相等断言
  - `assert_not_empty()`: 非空断言
  - `assert_greater()`: 大于断言
  - 测试结果统计

- [ ] 数据库测试
  - [ ] `test_db_connection()`: 数据库连接
  - [ ] `test_table_creation()`: 表结构创建
  - [ ] `test_index_creation()`: 索引创建
  - [ ] `test_trigger_function()`: 触发器功能
  - [ ] `test_view_creation()`: 视图创建

- [ ] 会话管理测试
  - [ ] `test_session_creation()`: 会话创建
  - [ ] `test_session_update()`: 会话更新
  - [ ] `test_session_termination()`: 会话终止
  - [ ] `test_duration_calculation()`: 时长计算

- [ ] 消息记录测试
  - [ ] `test_message_insert()`: 消息插入
  - [ ] `test_special_characters()`: 特殊字符转义
  - [ ] `test_empty_message()`: 空消息处理

- [ ] 清理功能测试
  - [ ] `test_cleanup_abnormal()`: 异常会话清理
  - [ ] `test_cleanup_timeout()`: 超时会话清理
  - [ ] `test_vacuum()`: 数据库维护

- [ ] 查询功能测试
  - [ ] `test_query_today()`: 今日查询
  - [ ] `test_query_stats()`: 统计查询
  - [ ] `test_export_csv()`: CSV 导出
  - [ ] `test_export_json()`: JSON 导出

**验收标准**:
- 所有单元测试通过
- 测试覆盖率 > 80%
- 边界条件测试充分

---

#### 5.2 集成测试

**任务**: 完整流程测试

**详细内容**:
- [ ] **正常流程测试**
  - 模拟 SessionStart Hook
  - 等待一段时间
  - 模拟 Stop Hook
  - 验证：
    - 数据库中会话状态为 'completed'
    - 时长计算正确
    - 通知发送成功
    - statistics 表更新

- [ ] **异常退出测试**
  - 启动会话
  - 模拟进程异常终止（kill -9）
  - 运行 cleanup.sh
  - 验证：
    - 会话状态为 'terminated'
    - 记录 AbnormalTermination 事件

- [ ] **终端关闭测试**
  - 启动会话后关闭终端
  - 等待守护进程运行（5分钟）
  - 验证：
    - 会话被自动标记为 terminated

- [ ] **并发会话测试**
  - 在多个终端同时启动 Claude Code
  - 验证：
    - 每个终端有独立的会话记录
    - 数据不冲突

- [ ] **Notification 测试**
  - 模拟 Notification Hook
  - 验证：
    - 系统通知显示
    - 终端窗口激活
    - 事件记录到数据库

**验收标准**:
- 所有集成测试场景通过
- 无数据竞争或死锁
- 通知系统正常工作

---

#### 5.3 性能测试

**任务**: 验证性能指标

**详细内容**:
- [ ] **Hook 执行时间测试**
  - 测量每个 Hook 的执行时间
  - 目标：< 50ms
  - 使用 `time` 命令测量

- [ ] **数据库查询性能**
  - 测试常用查询（today, stats, active）
  - 目标：< 10ms
  - 使用 EXPLAIN QUERY PLAN 分析

- [ ] **通知延迟测试**
  - 测量 Stop 事件到通知显示的时间
  - 目标：< 100ms

- [ ] **内存占用测试**
  - 测量脚本运行时内存使用
  - 目标：< 5MB

- [ ] **数据库大小测试**
  - 模拟1年数据（每天10个会话）
  - 目标：< 10MB

**验收标准**:
- 所有性能指标达到目标
- 在大量数据下性能稳定

---

#### 5.4 边界测试

**任务**: 测试边界条件和异常情况

**详细内容**:
- [ ] 特殊字符测试
  - 消息包含单引号、双引号
  - 消息包含换行符
  - 消息包含 SQL 关键字

- [ ] 空值测试
  - 空消息
  - 空项目名称
  - NULL 值处理

- [ ] 数据库锁定测试
  - 多个脚本同时写入
  - VACUUM 期间的查询

- [ ] 大数据量测试
  - 单个会话包含大量消息
  - 单日包含大量会话

- [ ] 系统资源限制测试
  - 磁盘空间不足
  - 权限不足

**验收标准**:
- 所有边界情况正确处理
- 错误消息清晰友好
- 不会导致数据损坏

---

### Phase 6: 文档与优化 (第11天)

#### 6.1 文档完善

**任务**: 创建用户文档

**详细内容**:
- [ ] **README.md**
  - 项目介绍
  - 功能特性
  - 快速开始
  - 使用示例
  - 常见问题
  - 卸载说明

- [ ] **INSTALL.md**
  - 系统要求
  - 依赖检查
  - 安装步骤
  - Claude Code Hooks 配置
  - 守护进程配置（可选）
  - 故障排查

- [ ] **代码注释完善**
  - 每个函数添加注释说明
  - 关键逻辑添加行内注释
  - SQL 语句添加注释

- [ ] **示例配置文件**
  - hooks.json 示例
  - .zshrc 配置示例

**验收标准**:
- 文档清晰易懂
- 步骤完整可复现
- 示例代码正确

---

#### 6.2 性能优化

**任务**: 根据测试结果优化性能

**详细内容**:
- [ ] **SQL 优化**
  - 分析慢查询
  - 优化索引使用
  - 避免全表扫描

- [ ] **脚本优化**
  - 减少子进程调用
  - 优化字符串处理
  - 减少重复查询

- [ ] **通知优化**
  - 考虑异步发送通知（如果需要）
  - 减少 osascript 调用次数

- [ ] **日志优化**
  - 日志轮转机制
  - 限制日志文件大小

**验收标准**:
- Hook 执行时间 < 50ms
- 数据库查询 < 10ms
- 通知延迟 < 100ms

---

#### 6.3 代码审查与重构

**任务**: 代码质量提升

**详细内容**:
- [ ] 代码规范检查
  - 统一缩进（4空格）
  - 统一引号使用
  - 函数命名规范

- [ ] 错误处理改进
  - 所有脚本使用 `set -euo pipefail`
  - 添加错误信息输出
  - 异常情况优雅处理

- [ ] 安全性检查
  - SQL 注入防护
  - 路径遍历防护
  - 权限检查

- [ ] 可维护性改进
  - 提取常量配置
  - 函数模块化
  - 减少代码重复

**验收标准**:
- 无 shellcheck 警告
- 安全扫描无问题
- 代码可读性良好

---

## 交付物清单

### 核心脚本 (6个)
- [x] `scripts/init.sh` - 数据库初始化脚本 **（简化版，仅创建目录）**
- [x] `scripts/record.sh` - 事件记录脚本 **（已完成，支持 4 种事件）**
- [ ] `scripts/cleanup.sh` - 异常清理脚本 **（待实现）**
- [x] `scripts/query.sh` - 查询工具脚本 **（已完成）**
- [x] `install.sh` - 安装脚本 **（已完成，自动配置 Hooks）**
- [ ] `uninstall.sh` - 卸载脚本 **（待验证）**

### 配置文件 (1个)
- [ ] `com.claude.monitor.plist` - LaunchAgent 配置

### 测试脚本 (1个)
- [ ] `test.sh` - 自动化测试脚本

### 文档 (4个)
- [ ] `plan.md` - 实施计划（本文档）
- [ ] `README.md` - 用户使用指南
- [ ] `INSTALL.md` - 安装说明
- [ ] `CLAUDE.md` - Claude Code 指南（已创建）

---

## 技术要点总结

### 1. 数据库设计
- **4表结构**: sessions, messages, events, statistics
- **sessions 表新增字段**: `last_prompt_time` DATETIME（用于精确计算单次对话耗时）
- **5个索引**: 优化常用查询（status_time, project, session_id等）
- **1个触发器**: 自动更新 updated_at
- **2个视图**: active_sessions, today_stats
- **当前状态**: ❌ 数据库文件为空，需要重新实现 init.sh 的数据库初始化逻辑

### 2. 异常处理
- **进程检测**: 使用 `kill -0 $pid` 检测进程存活
- **超时清理**: 自动清理运行超过24小时的会话
- **守护进程**: LaunchAgent 每5分钟执行清理

### 3. 通知系统
- **macOS 集成**: 使用 terminal-notifier（推荐）或 osascript（备选）
- **智能统计**: 显示今日会话次数和平均时长
- **精确耗时**: 基于 last_prompt_time 计算单次对话耗时
- **多种通知**: 启动、完成、错误三种通知类型
- **后台执行**: 使用 & 确保不阻塞 Hook 执行

### 4. 会话管理
- **UUID 生成**: `$(date +%s)-$$-$RANDOM` 确保唯一性，或使用 Hook 传入的 session_id
- **状态机**: running → completed/terminated
- **时长计算**:
  - 总时长: 从 start_time 到 end_time
  - 单次对话耗时: 从 last_prompt_time 到 stop/session_end
  - 使用 SQLite julianday 函数计算秒数
- **事件类型**: SessionStart (startup/resume), UserPromptSubmit, Stop, SessionEnd, Error

### 5. 性能目标
- **Hook 执行**: < 50ms
- **数据库查询**: < 10ms
- **通知延迟**: < 100ms
- **内存占用**: < 5MB
- **数据库大小**: < 10MB (1年数据)

---

## 风险与对策

### 风险1: Hook 执行超时
**影响**: 阻塞 Claude Code，影响用户体验
**对策**:
- 优化 SQL 查询，使用索引
- 考虑异步处理通知
- 限制日志写入操作

### 风险2: 数据库损坏
**影响**: 历史数据丢失
**对策**:
- 定期备份（每天/每周）
- 使用事务保证原子性
- 提供数据导出功能

### 风险3: 进程检测误判
**影响**: 正常会话被标记为异常
**对策**:
- 使用可靠的进程检测方法 (`kill -0`)
- 24小时超时作为兜底
- 记录详细日志便于排查

### 风险4: 特殊字符注入
**影响**: SQL 注入或脚本执行错误
**对策**:
- SQL 转义（单引号 `'` → `''`）
- 考虑使用参数化查询
- 输入验证

### 风险5: 性能影响
**影响**: Claude Code 启动/停止缓慢
**对策**:
- 性能测试验证
- 优化热点代码
- 异步处理非关键操作

---

## 验收标准

### 功能完整性
- [ ] 所有 PRD 需求已实现
- [ ] 4种 Hook 事件正确处理
- [ ] 7个查询命令功能正常
- [ ] 数据导出功能正常
- [ ] 异常清理功能正常

### 质量标准
- [ ] 单元测试通过率 100%
- [ ] 集成测试通过率 100%
- [ ] 性能测试达标
- [ ] 无 shellcheck 警告
- [ ] 代码注释完整

### 文档完整性
- [ ] README.md 清晰易懂
- [ ] INSTALL.md 步骤完整
- [ ] 代码注释详细
- [ ] 示例配置正确

### 用户体验
- [ ] 安装过程顺畅
- [ ] 错误提示友好
- [ ] 通知信息清晰
- [ ] 查询输出美观

---

## 后续迭代计划

### Phase 1 (v1.1) - 跨平台支持
- [ ] 支持 Linux 通知系统 (notify-send)
- [ ] 支持 Windows (PowerShell + Toast 通知)
- [ ] Web 界面查看统计
- [ ] 数据可视化（图表）

### Phase 2 (v1.2) - 高级功能
- [ ] 云端同步（可选）
- [ ] 多设备支持
- [ ] RESTful API 接口
- [ ] 数据备份与恢复

### Phase 3 (v2.0) - 智能化
- [ ] AI 分析使用模式
- [ ] 智能提醒（长时间运行警告）
- [ ] 项目时间统计报告
- [ ] 团队协作功能（多用户）

---

## 附录

### A. 开发环境要求
- macOS 10.15+
- Bash 3.2+
- SQLite 3.x
- Python 3.x (用于 install.sh 自动配置 Hooks)
- Claude Code (最新版本)
- terminal-notifier (推荐，可通过 brew install terminal-notifier 安装)

### B. 依赖工具
- `sqlite3`: 数据库管理（必需）
- `terminal-notifier`: macOS 通知（推荐，比 osascript 更可靠）
- `osascript`: macOS 通知（备选）
- `jq`: JSON 处理（用于解析 Hook 输入和 export）（必需）
- `python3`: 自动配置 Hooks 到 settings.json（必需）
- `launchctl`: 守护进程管理（可选）

### C. 参考资料
- [SQLite Documentation](https://www.sqlite.org/docs.html)
- [Bash Shell Scripting Guide](https://www.gnu.org/software/bash/manual/)
- [macOS LaunchAgent Guide](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
- [AppleScript Language Guide](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/)

---

**文档结束**
