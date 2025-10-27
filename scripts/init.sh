#!/bin/bash
# ~/.claude/claude-code-helper/scripts/init.sh
# Claude Code Monitor - 数据库初始化脚本

set -e

# 目录配置
CLAUDE_DIR="$HOME/.claude"
APP_DIR="$CLAUDE_DIR/claude-code-helper"
DB_PATH="$CLAUDE_DIR/monitor.db"          # 数据库放在 Claude 根目录
LOG_DIR="$APP_DIR/logs"
SCRIPTS_DIR="$APP_DIR/scripts"
BACKUPS_DIR="$APP_DIR/backups"

echo "🚀 初始化 Claude Code Monitor..."

# 创建目录结构（应该已由 install.sh 创建，这里再确保一次）
echo "📁 确认目录结构..."
mkdir -p "$APP_DIR"/{scripts,logs,backups}

# 创建测试日志文件,确认目录可写
TEST_LOG="$LOG_DIR/init_test.log"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 初始化测试 - 日志目录可写" > "$TEST_LOG"

if [ -f "$TEST_LOG" ]; then
    echo "✅ 日志目录创建成功: $LOG_DIR"
else
    echo "❌ 错误: 无法创建日志文件"
    exit 1
fi

# 创建主日志文件
MAIN_LOG="$LOG_DIR/monitor.log"
echo "========================================" > "$MAIN_LOG"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Claude Code Monitor 初始化" >> "$MAIN_LOG"
echo "应用目录: $APP_DIR" >> "$MAIN_LOG"
echo "日志目录: $LOG_DIR" >> "$MAIN_LOG"
echo "脚本目录: $SCRIPTS_DIR" >> "$MAIN_LOG"
echo "数据库路径: $DB_PATH" >> "$MAIN_LOG"
echo "========================================" >> "$MAIN_LOG"
echo "" >> "$MAIN_LOG"

# 初始化数据库
echo "📊 初始化数据库..."
sqlite3 "$DB_PATH" << 'EOF'
-- 创建 sessions 表
CREATE TABLE IF NOT EXISTS sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_uuid TEXT UNIQUE,
    start_time DATETIME NOT NULL,
    end_time DATETIME,
    duration INTEGER,
    last_prompt_time DATETIME,
    status TEXT DEFAULT 'running' CHECK(status IN ('running', 'completed', 'terminated')),
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
    message_type TEXT DEFAULT 'user' CHECK(message_type IN ('user', 'system', 'error')),
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
CREATE INDEX IF NOT EXISTS idx_statistics_date ON statistics(date);

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

# 验证数据库创建
TABLE_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';")
INDEX_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%';")
VIEW_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='view';")
TRIGGER_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger';")

echo "✅ 数据库初始化完成: $DB_PATH"
echo "   - 表: $TABLE_COUNT 张"
echo "   - 索引: $INDEX_COUNT 个"
echo "   - 视图: $VIEW_COUNT 个"
echo "   - 触发器: $TRIGGER_COUNT 个"
echo ""
echo "📝 下一步操作:"
echo "   1. 运行 ./install.sh 完成安装"
echo "   2. 安装脚本会自动配置 Claude Code Hooks"
echo "   3. 启动 Claude Code 后,检查日志: tail -f $MAIN_LOG"
echo ""
