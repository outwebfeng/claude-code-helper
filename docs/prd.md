# Claude Code 监控系统 PRD
**产品需求文档 v1.0**

## 1. 产品概述

### 1.1 产品定位
Claude Code 监控系统是一个轻量级的本地监控工具，通过 Claude Hooks 机制和 SQLite 数据库，实现对 Claude Code 会话的全生命周期监控、数据记录和智能通知。

### 1.2 核心价值
- **零侵入**：基于官方 Hooks 机制，不修改 Claude Code 本体
- **轻量级**：使用 SQLite + Shell 脚本，资源占用极低
- **数据持久化**：完整记录会话历史，支持统计分析
- **智能通知**：任务完成自动提醒，提升工作效率

### 1.3 目标用户
- Claude Code 重度用户
- 需要追踪 AI 辅助编程时间的开发者
- 希望优化工作流程的技术人员

## 2. 功能需求

### 2.1 核心功能

#### 2.1.1 会话记录
- **记录内容**：
  - 会话开始/结束时间
  - 执行时长（自动计算）
  - 用户发送的消息（提问内容）
  - 项目名称和路径
  - 会话状态（running/completed/terminated）
  
#### 2.1.2 通知系统
- **通知时机**：
  - 会话正常完成
  - 需要用户输入
  - 异常终止
  
- **通知内容**：
  - 执行时长
  - 今日统计（第N次，平均耗时）
  - 项目名称

#### 2.1.3 异常处理
- **检测场景**：
  - 正常退出（Stop 事件）
  - 强制退出（Ctrl+C）
  - 终端关闭
  - 系统关机/重启
  - 网络中断

- **处理策略**：
  - 标记会话状态为 `terminated`
  - 记录异常类型
  - 下次启动时自动清理

### 2.2 数据查询功能
- 查看今日会话列表
- 统计分析（总时长、平均时长、项目分布）
- 查询历史记录
- 导出数据（CSV/JSON）

## 3. 技术架构

### 3.1 系统架构图
```
┌─────────────────────────────────────────────┐
│                Claude Code                  │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │         Hooks Configuration         │   │
│  └────────────┬────────────────────────┘   │
│               │                             │
│     ┌─────────┼─────────┬──────────┐       │
│     ▼         ▼         ▼          ▼       │
│ SessionStart  Stop  Notification  Error    │
└─────┬─────────┬─────────┬──────────┬───────┘
      │         │         │          │
      ▼         ▼         ▼          ▼
┌─────────────────────────────────────────────┐
│           Shell Script Layer                │
│  ┌──────────────┐  ┌──────────────┐        │
│  │ record.sh    │  │ notify.sh    │        │
│  │ cleanup.sh   │  │ query.sh     │        │
│  └──────┬───────┘  └──────┬───────┘        │
│         │                  │                 │
│         ▼                  ▼                 │
│    ┌─────────────────────────────┐          │
│    │    SQLite Database          │          │
│    │    ~/.claude/monitor.db     │          │
│    └─────────────────────────────┘          │
└─────────────────────────────────────────────┘
```

### 3.2 技术栈
- **数据库**：SQLite 3.x
- **脚本语言**：Bash Shell
- **通知系统**：terminal-notifier (推荐) 或 macOS osascript (备选)
- **配置格式**：JSON
- **定时任务**：launchd（用于异常清理）
- **JSON 解析**：jq (用于解析 hook 输入)

## 4. 数据模型

### 4.1 数据库设计

#### sessions 表
```sql
CREATE TABLE sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_uuid TEXT UNIQUE,              -- 会话唯一标识
    start_time DATETIME NOT NULL,          -- 开始时间
    end_time DATETIME,                     -- 结束时间
    duration INTEGER,                      -- 时长（秒）
    last_prompt_time DATETIME,             -- 最后一次用户提问时间（用于计算单次对话耗时）
    status TEXT CHECK(status IN ('running', 'completed', 'terminated')),
    project_name TEXT,                     -- 项目名称
    project_path TEXT,                     -- 项目路径
    pid INTEGER,                           -- Claude进程ID
    terminal_session TEXT,                 -- 终端会话标识
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

#### messages 表
```sql
CREATE TABLE messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    message_type TEXT CHECK(message_type IN ('user', 'system', 'error')),
    content TEXT NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);
```

#### events 表
```sql
CREATE TABLE events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    event_type TEXT NOT NULL,              -- SessionStart/Stop/Notification/Error
    event_data TEXT,                       -- JSON格式的额外数据
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);
```

#### statistics 表（汇总表，用于快速查询）
```sql
CREATE TABLE statistics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date DATE UNIQUE,
    total_sessions INTEGER DEFAULT 0,
    total_duration INTEGER DEFAULT 0,
    avg_duration INTEGER DEFAULT 0,
    completed_count INTEGER DEFAULT 0,
    terminated_count INTEGER DEFAULT 0,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

### 4.2 索引设计
```sql
CREATE INDEX idx_sessions_status_time ON sessions(status, start_time);
CREATE INDEX idx_sessions_project ON sessions(project_name);
CREATE INDEX idx_messages_session ON messages(session_id);
CREATE INDEX idx_events_session_type ON events(session_id, event_type);
CREATE INDEX idx_statistics_date ON statistics(date);
```

## 5. 详细实现方案

### 5.1 目录结构
```
~/.claude/
├── monitor.db                 # SQLite数据库
├── settings.json              # Claude Code配置文件（包含Hooks配置）
├── scripts/                   # 脚本目录
│   ├── init.sh               # 初始化脚本（简化版：仅创建目录）
│   ├── record.sh             # 记录事件（SessionStart/Stop/UserPromptSubmit/SessionEnd）
│   ├── cleanup.sh            # 清理异常会话（待实现）
│   └── query.sh              # 查询工具
├── logs/                     # 日志目录
│   ├── monitor.log          # 运行日志
│   └── hook_debug.log       # Hook调试日志
└── backups/                 # 备份目录
```

### 5.2 核心脚本实现

#### 5.2.1 初始化脚本 (init.sh)
```bash
#!/bin/bash
# ~/.claude/scripts/init.sh

set -e

CLAUDE_DIR="$HOME/.claude"
DB_PATH="$CLAUDE_DIR/monitor.db"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"

# 创建目录结构
mkdir -p "$CLAUDE_DIR"/{scripts,logs,backups}

# 初始化数据库
sqlite3 "$DB_PATH" << 'EOF'
-- 创建 sessions 表
CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_uuid TEXT UNIQUE,
    start_time DATETIME NOT NULL,
    end_time DATETIME,
    duration INTEGER,
    status TEXT DEFAULT 'running',
    project_name TEXT,
    project_path TEXT,
    pid INTEGER,
    terminal_session TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 创建 messages 表
CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    message_type TEXT DEFAULT 'user',
    content TEXT NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

-- 创建 events 表
CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    event_type TEXT NOT NULL,
    event_data TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
);

-- 创建统计表
CREATE TABLE IF NOT EXISTS statistics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    date DATE UNIQUE,
    total_sessions INTEGER DEFAULT 0,
    total_duration INTEGER DEFAULT 0,
    avg_duration INTEGER DEFAULT 0,
    completed_count INTEGER DEFAULT 0,
    terminated_count INTEGER DEFAULT 0,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_sessions_status_time ON sessions(status, start_time);
CREATE INDEX IF NOT EXISTS idx_sessions_project ON sessions(project_name);
CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id);
CREATE INDEX IF NOT EXISTS idx_events_session_type ON events(session_id, event_type);

-- 创建触发器：自动更新 updated_at
CREATE TRIGGER IF NOT EXISTS update_sessions_timestamp
AFTER UPDATE ON sessions
FOR EACH ROW
BEGIN
    UPDATE sessions SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

-- 创建视图：活跃会话
CREATE VIEW IF NOT EXISTS active_sessions AS
SELECT * FROM sessions WHERE status = 'running';

-- 创建视图：今日统计
CREATE VIEW IF NOT EXISTS today_stats AS
SELECT 
    COUNT(*) as total_sessions,
    COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed,
    COUNT(CASE WHEN status = 'terminated' THEN 1 END) as terminated,
    AVG(duration) as avg_duration,
    SUM(duration) as total_duration
FROM sessions 
WHERE date(start_time) = date('now', 'localtime');

EOF

echo "✅ Database initialized at: $DB_PATH"

# Hooks 配置已移至 install.sh
# install.sh 会使用 Python 自动将 Hooks 配置添加到 ~/.claude/settings.json
#
# Hooks 配置结构:
# {
#   "hooks": {
#     "SessionStart": [
#       {
#         "matcher": "startup",
#         "hooks": [{"type": "command", "command": "~/.claude/scripts/record.sh start"}]
#       },
#       {
#         "matcher": "resume",
#         "hooks": [{"type": "command", "command": "~/.claude/scripts/record.sh start"}]
#       }
#     ],
#     "UserPromptSubmit": [
#       {"hooks": [{"type": "command", "command": "~/.claude/scripts/record.sh user_prompt"}]}
#     ],
#     "Stop": [
#       {"hooks": [{"type": "command", "command": "~/.claude/scripts/record.sh stop"}]}
#     ],
#     "SessionEnd": [
#       {"hooks": [{"type": "command", "command": "~/.claude/scripts/record.sh session_end"}]}
#     ]
#   }
# }

echo "✅ Hooks will be configured automatically by install.sh"
```

#### 5.2.2 事件记录脚本 (record.sh)
```bash
#!/bin/bash
# ~/.claude/scripts/record.sh

set -euo pipefail

DB_PATH="$HOME/.claude/monitor.db"
LOG_PATH="$HOME/.claude/logs/monitor.log"
EVENT_TYPE="${1:-unknown}"

# 从 stdin 读取 JSON 输入（Claude Code Hooks 传入）
if [ -t 0 ]; then
    # stdin 是终端（手动执行）
    HOOK_INPUT=""
    MESSAGE="${2:-}"
    SESSION_ID_FROM_HOOK=""
    SOURCE_TYPE=""
else
    # stdin 有数据（Hook 执行）
    HOOK_INPUT=$(cat)
    # 尝试提取 prompt 或 message 字段
    MESSAGE=$(echo "$HOOK_INPUT" | jq -r '.prompt // .message // ""' 2>/dev/null || echo "")
    SESSION_ID_FROM_HOOK=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")
    SOURCE_TYPE=$(echo "$HOOK_INPUT" | jq -r '.source // ""' 2>/dev/null || echo "")
fi

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_PATH"
}

# 生成会话UUID
generate_uuid() {
    echo "$(date +%s)-$$-$RANDOM"
}

# 获取项目信息
get_project_info() {
    PROJECT_PATH="$PWD"
    PROJECT_NAME=$(basename "$PROJECT_PATH")
    echo "$PROJECT_NAME|$PROJECT_PATH"
}

# 获取终端会话信息
get_terminal_session() {
    echo "$TERM_SESSION_ID"  # macOS Terminal
}

# 获取或创建当前会话
get_or_create_session() {
    local session_id
    
    # 查找运行中的会话
    session_id=$(sqlite3 "$DB_PATH" \
        "SELECT id FROM sessions WHERE status='running' ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")
    
    if [ -z "$session_id" ]; then
        # 创建新会话
        local uuid=$(generate_uuid)
        local project_info=$(get_project_info)
        local project_name=$(echo "$project_info" | cut -d'|' -f1)
        local project_path=$(echo "$project_info" | cut -d'|' -f2)
        local terminal_session=$(get_terminal_session)
        
        sqlite3 "$DB_PATH" << EOF
INSERT INTO sessions (session_uuid, start_time, status, project_name, project_path, pid, terminal_session)
VALUES ('$uuid', datetime('now'), 'running', '$project_name', '$project_path', $$, '$terminal_session');
EOF
        session_id=$(sqlite3 "$DB_PATH" "SELECT last_insert_rowid()")
        log "Created new session: $session_id"
    fi
    
    echo "$session_id"
}

# 记录消息
record_message() {
    local session_id=$1
    local content=$2
    
    if [ -n "$content" ]; then
        # 转义单引号
        content="${content//\'/\'\'}"
        
        sqlite3 "$DB_PATH" << EOF
INSERT INTO messages (session_id, message_type, content)
VALUES ($session_id, 'user', '$content');
EOF
        log "Recorded message for session $session_id"
    fi
}

# 记录事件
record_event() {
    local session_id=$1
    local event_type=$2
    local event_data=${3:-}
    
    sqlite3 "$DB_PATH" << EOF
INSERT INTO events (session_id, event_type, event_data)
VALUES ($session_id, '$event_type', '$event_data');
EOF
    log "Recorded event: $event_type for session $session_id"
}

# 处理不同事件
case "$EVENT_TYPE" in
    start|SessionStart)
        SESSION_ID=$(get_or_create_session)
        record_event "$SESSION_ID" "SessionStart" "{\"pwd\":\"$PWD\"}"
        record_message "$SESSION_ID" "$MESSAGE"
        log "Session started: $SESSION_ID"
        ;;
        
    stop|Stop)
        SESSION_ID=$(get_or_create_session)
        
        # 更新会话状态和时长
        sqlite3 "$DB_PATH" << EOF
UPDATE sessions 
SET 
    end_time = datetime('now'),
    duration = CAST((julianday(datetime('now')) - julianday(start_time)) * 86400 AS INTEGER),
    status = 'completed'
WHERE id = $SESSION_ID;
EOF
        
        record_event "$SESSION_ID" "Stop" ""
        
        # 获取统计信息
        STATS=$(sqlite3 "$DB_PATH" -separator '|' << EOF
SELECT 
    s.duration,
    s.project_name,
    (SELECT COUNT(*) FROM sessions WHERE date(start_time) = date('now', 'localtime')),
    (SELECT ROUND(AVG(duration)) FROM sessions WHERE date(start_time) = date('now', 'localtime') AND status='completed')
FROM sessions s
WHERE s.id = $SESSION_ID;
EOF
        )
        
        DURATION=$(echo "$STATS" | cut -d'|' -f1)
        PROJECT=$(echo "$STATS" | cut -d'|' -f2)
        TODAY_COUNT=$(echo "$STATS" | cut -d'|' -f3)
        TODAY_AVG=$(echo "$STATS" | cut -d'|' -f4)
        
        # 格式化时长
        if [ "$DURATION" -lt 60 ]; then
            DURATION_STR="${DURATION}秒"
        elif [ "$DURATION" -lt 3600 ]; then
            DURATION_STR="$((DURATION/60))分$((DURATION%60))秒"
        else
            DURATION_STR="$((DURATION/3600))小时$((DURATION%3600/60))分"
        fi
        
        if [ "$TODAY_AVG" -lt 60 ]; then
            AVG_STR="${TODAY_AVG}秒"
        else
            AVG_STR="$((TODAY_AVG/60))分钟"
        fi
        
        # 发送通知（使用 terminal-notifier）
        send_notification() {
            local title="$1"
            local message="$2"
            local sound="${3:-default}"

            if command -v terminal-notifier &> /dev/null; then
                terminal-notifier -title "$title" -message "$message" -sound "$sound" &
            else
                log "WARNING: terminal-notifier not found, skipping notification"
            fi
        }

        send_notification "✅ Claude Code 完成" \
            "项目: $PROJECT
耗时: $DURATION_STR
今日: 第${TODAY_COUNT}次, 平均${AVG_STR}" \
            "Glass"
        
        log "Session completed: $SESSION_ID, Duration: $DURATION seconds"
        
        # 更新统计表
        sqlite3 "$DB_PATH" << EOF
INSERT OR REPLACE INTO statistics (date, total_sessions, total_duration, avg_duration, completed_count)
SELECT 
    date('now', 'localtime'),
    COUNT(*),
    SUM(duration),
    AVG(duration),
    COUNT(CASE WHEN status='completed' THEN 1 END)
FROM sessions 
WHERE date(start_time) = date('now', 'localtime');
EOF
        ;;
        
    user_prompt|UserPromptSubmit)
        log "========== UserPromptSubmit Hook Triggered =========="
        SESSION_ID=$(get_or_create_session)

        record_message "$SESSION_ID" "$MESSAGE"
        record_event "$SESSION_ID" "UserPromptSubmit" "{\"message\":\"$MESSAGE\"}"

        # 记录用户提问时间，用于计算单次对话耗时
        sqlite3 "$DB_PATH" << EOF
UPDATE sessions
SET last_prompt_time = datetime('now')
WHERE id = $SESSION_ID;
EOF
        log "User message recorded for session $SESSION_ID, prompt time updated"
        ;;

    session_end|SessionEnd)
        log "========== SessionEnd Hook Triggered =========="
        SESSION_ID=$(get_or_create_session)

        record_event "$SESSION_ID" "SessionEnd" "{}"

        # 检查是否有 last_prompt_time（说明用户提交过问题）
        LAST_PROMPT_TIME=$(sqlite3 "$DB_PATH" "SELECT last_prompt_time FROM sessions WHERE id=$SESSION_ID")

        if [ -n "$LAST_PROMPT_TIME" ] && [ "$LAST_PROMPT_TIME" != "" ]; then
            # 计算单次对话耗时并发送通知
            DURATION=$(sqlite3 "$DB_PATH" \
                "SELECT CAST((julianday(datetime('now')) - julianday('$LAST_PROMPT_TIME')) * 86400 AS INTEGER)")

            # 更新会话状态并发送完成通知
            # ... (类似 Stop 事件处理)
        else
            # 没有提交问题，只标记会话结束，不发送通知
            log "No user prompt recorded, marking session as completed without notification"
        fi
        ;;

    error|Error)
        SESSION_ID=$(get_or_create_session)
        record_event "$SESSION_ID" "Error" "{\"error\":\"$MESSAGE\"}"
        
        # 标记会话为异常终止
        sqlite3 "$DB_PATH" << EOF
UPDATE sessions 
SET 
    end_time = datetime('now'),
    duration = CAST((julianday(datetime('now')) - julianday(start_time)) * 86400 AS INTEGER),
    status = 'terminated'
WHERE id = $SESSION_ID;
EOF
        
        log "Error recorded for session $SESSION_ID: $MESSAGE"
        ;;
        
    *)
        log "Unknown event type: $EVENT_TYPE"
        exit 1
        ;;
esac
```

#### 5.2.3 异常清理脚本 (cleanup.sh)
```bash
#!/bin/bash
# ~/.claude/scripts/cleanup.sh

set -euo pipefail

DB_PATH="$HOME/.claude/monitor.db"
LOG_PATH="$HOME/.claude/logs/monitor.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] CLEANUP: $1" >> "$LOG_PATH"
}

# 检查并清理异常会话
cleanup_abnormal_sessions() {
    # 获取所有运行中的会话
    RUNNING_SESSIONS=$(sqlite3 "$DB_PATH" -separator '|' \
        "SELECT id, pid, session_uuid FROM sessions WHERE status='running'")
    
    if [ -z "$RUNNING_SESSIONS" ]; then
        log "No running sessions to check"
        return
    fi
    
    # 检查每个会话的进程是否还在运行
    echo "$RUNNING_SESSIONS" | while IFS='|' read -r session_id pid session_uuid; do
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            # 进程已不存在，标记为异常终止
            sqlite3 "$DB_PATH" << EOF
UPDATE sessions 
SET 
    end_time = datetime('now'),
    status = 'terminated',
    duration = CAST((julianday(datetime('now')) - julianday(start_time)) * 86400 AS INTEGER)
WHERE id = $session_id;

INSERT INTO events (session_id, event_type, event_data)
VALUES ($session_id, 'AbnormalTermination', '{"reason":"process_not_found"}');
EOF
            log "Marked session $session_id as terminated (PID $pid not found)"
        fi
    done
}

# 清理超时会话（超过24小时仍在运行）
cleanup_timeout_sessions() {
    sqlite3 "$DB_PATH" << EOF
UPDATE sessions 
SET 
    status = 'terminated',
    end_time = datetime('now')
WHERE 
    status = 'running' 
    AND datetime(start_time) < datetime('now', '-24 hours');
EOF
    
    local affected=$(sqlite3 "$DB_PATH" "SELECT changes()")
    if [ "$affected" -gt 0 ]; then
        log "Cleaned up $affected timeout sessions"
    fi
}

# 主函数
main() {
    log "Starting cleanup process"
    
    cleanup_abnormal_sessions
    cleanup_timeout_sessions
    
    # 执行数据库维护
    sqlite3 "$DB_PATH" "VACUUM"
    
    log "Cleanup process completed"
}

main "$@"
```

#### 5.2.4 查询工具 (query.sh)
```bash
#!/bin/bash
# ~/.claude/scripts/query.sh

set -euo pipefail

DB_PATH="$HOME/.claude/monitor.db"
COMMAND="${1:-help}"

# 彩色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

case "$COMMAND" in
    today)
        echo -e "${BLUE}=== 今日会话 ===${NC}"
        sqlite3 "$DB_PATH" -column -header << EOF
.width 8 20 10 10 30
SELECT 
    strftime('%H:%M', start_time) as "开始时间",
    CASE 
        WHEN duration < 60 THEN duration || 's'
        WHEN duration < 3600 THEN (duration/60) || 'm' || (duration%60) || 's'
        ELSE (duration/3600) || 'h' || ((duration%3600)/60) || 'm'
    END as "耗时",
    status as "状态",
    substr(project_name, 1, 30) as "项目"
FROM sessions 
WHERE date(start_time) = date('now', 'localtime')
ORDER BY start_time DESC;
EOF
        ;;
        
    stats)
        echo -e "${BLUE}=== 统计信息 ===${NC}"
        sqlite3 "$DB_PATH" << EOF
.mode line
SELECT 
    '今日会话' as metric, COUNT(*) as value 
FROM sessions 
WHERE date(start_time) = date('now', 'localtime')
UNION ALL
SELECT 
    '今日完成', COUNT(*) 
FROM sessions 
WHERE date(start_time) = date('now', 'localtime') AND status='completed'
UNION ALL
SELECT 
    '今日总时长(小时)', ROUND(SUM(duration)/3600.0, 2)
FROM sessions 
WHERE date(start_time) = date('now', 'localtime')
UNION ALL
SELECT 
    '平均时长(分钟)', ROUND(AVG(duration)/60.0, 1)
FROM sessions 
WHERE date(start_time) = date('now', 'localtime') AND status='completed'
UNION ALL
SELECT 
    '本周总会话', COUNT(*)
FROM sessions 
WHERE date(start_time) >= date('now', 'localtime', 'weekday 0', '-7 days')
UNION ALL
SELECT 
    '本周总时长(小时)', ROUND(SUM(duration)/3600.0, 2)
FROM sessions 
WHERE date(start_time) >= date('now', 'localtime', 'weekday 0', '-7 days');
EOF
        ;;
        
    active)
        echo -e "${YELLOW}=== 活跃会话 ===${NC}"
        sqlite3 "$DB_PATH" -column -header << EOF
.width 5 20 30 15
SELECT 
    id,
    strftime('%H:%M:%S', start_time) as "开始时间",
    project_name as "项目",
    CAST((julianday('now') - julianday(start_time)) * 86400 AS INTEGER) as "已运行(秒)"
FROM sessions 
WHERE status = 'running'
ORDER BY start_time DESC;
EOF
        ;;
        
    messages)
        SESSION_ID="${2:-}"
        if [ -z "$SESSION_ID" ]; then
            # 显示最近的消息
            echo -e "${BLUE}=== 最近消息 ===${NC}"
            sqlite3 "$DB_PATH" -column -header << EOF
.width 20 60
SELECT 
    strftime('%Y-%m-%d %H:%M', m.timestamp) as "时间",
    substr(m.content, 1, 60) as "消息"
FROM messages m
JOIN sessions s ON m.session_id = s.id
ORDER BY m.timestamp DESC
LIMIT 10;
EOF
        else
            # 显示特定会话的消息
            echo -e "${BLUE}=== 会话 #$SESSION_ID 消息 ===${NC}"
            sqlite3 "$DB_PATH" -column -header << EOF
.width 20 80
SELECT 
    strftime('%H:%M:%S', timestamp) as "时间",
    content as "消息"
FROM messages 
WHERE session_id = $SESSION_ID
ORDER BY timestamp;
EOF
        fi
        ;;
        
    export)
        FORMAT="${2:-csv}"
        OUTPUT_FILE="$HOME/claude_export_$(date +%Y%m%d_%H%M%S).$FORMAT"
        
        if [ "$FORMAT" = "csv" ]; then
            sqlite3 "$DB_PATH" -header -csv << EOF > "$OUTPUT_FILE"
SELECT 
    session_uuid,
    start_time,
    end_time,
    duration,
    status,
    project_name,
    project_path
FROM sessions 
ORDER BY start_time DESC;
EOF
            echo -e "${GREEN}✅ Exported to: $OUTPUT_FILE${NC}"
            
        elif [ "$FORMAT" = "json" ]; then
            sqlite3 "$DB_PATH" << EOF | jq '.' > "$OUTPUT_FILE"
SELECT json_group_array(json_object(
    'id', id,
    'session_uuid', session_uuid,
    'start_time', start_time,
    'end_time', end_time,
    'duration', duration,
    'status', status,
    'project_name', project_name
))
FROM sessions;
EOF
            echo -e "${GREEN}✅ Exported to: $OUTPUT_FILE${NC}"
        else
            echo -e "${RED}❌ Unknown format: $FORMAT${NC}"
            echo "Supported formats: csv, json"
        fi
        ;;
        
    clean)
        DAYS="${2:-30}"
        echo -e "${YELLOW}Cleaning sessions older than $DAYS days...${NC}"
        
        BEFORE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sessions")
        
        sqlite3 "$DB_PATH" << EOF
DELETE FROM sessions 
WHERE date(start_time) < date('now', '-$DAYS days');

DELETE FROM messages 
WHERE session_id NOT IN (SELECT id FROM sessions);

DELETE FROM events 
WHERE session_id NOT IN (SELECT id FROM sessions);

VACUUM;
EOF
        
        AFTER_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sessions")
        DELETED=$((BEFORE_COUNT - AFTER_COUNT))
        
        echo -e "${GREEN}✅ Deleted $DELETED old sessions${NC}"
        ;;
        
    help|*)
        echo -e "${BLUE}Claude Code Monitor - Query Tool${NC}"
        echo ""
        echo "Usage: $0 <command> [options]"
        echo ""
        echo "Commands:"
        echo "  today              - Show today's sessions"
        echo "  stats              - Show statistics"
        echo "  active             - Show active/running sessions"
        echo "  messages [id]      - Show messages (all or by session ID)"
        echo "  export [csv|json]  - Export data"
        echo "  clean [days]       - Clean old data (default: 30 days)"
        echo "  help              - Show this help"
        ;;
esac
```

### 5.3 守护进程（异常监控）

#### 5.3.1 LaunchAgent 配置
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claude.monitor</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>~/.claude/scripts/cleanup.sh</string>
    </array>
    
    <key>StartInterval</key>
    <integer>300</integer> <!-- 每5分钟运行一次 -->
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>~/.claude/logs/daemon.log</string>
    
    <key>StandardErrorPath</key>
    <string>~/.claude/logs/daemon_error.log</string>
</dict>
</plist>
```

### 5.4 安装脚本
```bash
#!/bin/bash
# install.sh

echo "🚀 Installing Claude Code Monitor..."

# 1. 运行初始化脚本
~/.claude/scripts/init.sh

# 2. 设置脚本权限
chmod +x ~/.claude/scripts/*.sh

# 3. 安装 LaunchAgent（可选）
if [ "$1" = "--with-daemon" ]; then
    cp com.claude.monitor.plist ~/Library/LaunchAgents/
    launchctl load ~/Library/LaunchAgents/com.claude.monitor.plist
    echo "✅ Daemon installed"
fi

# 4. 添加便捷命令到 shell 配置
echo 'alias claude-stats="~/.claude/scripts/query.sh stats"' >> ~/.zshrc
echo 'alias claude-today="~/.claude/scripts/query.sh today"' >> ~/.zshrc
echo 'alias claude-clean="~/.claude/scripts/cleanup.sh"' >> ~/.zshrc

echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "1. Copy ~/.claude/config.json to your Claude Code config location"
echo "2. Restart Claude Code"
echo "3. Run 'claude-stats' to view statistics"
```

## 6. 测试方案

### 6.1 单元测试
```bash
#!/bin/bash
# test.sh

# 测试数据库连接
test_db_connection() {
    sqlite3 ~/.claude/monitor.db "SELECT 1" &>/dev/null
    assert_equal $? 0 "Database connection"
}

# 测试会话创建
test_session_creation() {
    ~/.claude/scripts/record.sh start "Test message"
    SESSION_COUNT=$(sqlite3 ~/.claude/monitor.db "SELECT COUNT(*) FROM sessions WHERE status='running'")
    assert_greater $SESSION_COUNT 0 "Session creation"
}

# 测试异常清理
test_cleanup() {
    # 创建一个假的异常会话
    sqlite3 ~/.claude/monitor.db "INSERT INTO sessions (session_uuid, start_time, status, pid) VALUES ('test-123', datetime('now'), 'running', 99999)"
    ~/.claude/scripts/cleanup.sh
    TERMINATED=$(sqlite3 ~/.claude/monitor.db "SELECT COUNT(*) FROM sessions WHERE session_uuid='test-123' AND status='terminated'")
    assert_equal $TERMINATED 1 "Cleanup abnormal session"
}
```

### 6.2 集成测试场景
1. 正常流程：启动 → 记录 → 完成 → 通知
2. 异常退出：启动 → Ctrl+C → 清理
3. 终端关闭：启动 → 关闭终端 → 守护进程清理
4. 并发会话：多个终端同时运行

## 7. 性能指标

### 7.1 目标指标
- Hook 执行时间：< 50ms
- 数据库查询：< 10ms
- 通知延迟：< 100ms
- 内存占用：< 5MB（脚本执行期间）
- 数据库大小：< 10MB（1年数据）

### 7.2 优化措施
- 使用索引加速查询
- 定期清理历史数据
- 批量更新统计表
- 异步发送通知（如需要）

## 8. 后续迭代计划

### Phase 1 (v1.1)
- [ ] 支持 Linux 通知系统
- [ ] Web 界面查看统计
- [ ] 数据可视化（图表）

### Phase 2 (v1.2)
- [ ] 云端同步
- [ ] 多设备支持
- [ ] API 接口

### Phase 3 (v2.0)
- [ ] AI 分析使用模式
- [ ] 智能提醒
- [ ] 团队协作功能

## 9. 风险与对策

| 风险 | 影响 | 对策 |
|------|------|------|
| Claude API 变更 | Hooks 失效 | 版本兼容性检查 |
| 数据库损坏 | 数据丢失 | 定期备份 |
| 性能影响 | 用户体验 | 异步处理，优化查询 |
| 隐私问题 | 数据泄露 | 本地存储，加密敏感信息 |

## 10. 附录

### 10.1 常见问题
1. **Q: 如何卸载？**
   A: 运行 `~/.claude/scripts/uninstall.sh`

2. **Q: 数据存储在哪里？**
   A: `~/.claude/monitor.db`

3. **Q: 如何备份数据？**
   A: 使用 `query.sh export` 命令

### 10.2 参考资源
- [Claude Code Hooks Documentation](#)
- [SQLite Documentation](https://www.sqlite.org/docs.html)
- [macOS Notification Center](#)

---

**文档版本**: v1.0  
**最后更新**: 2024-01  
**作者**: Claude Assistant