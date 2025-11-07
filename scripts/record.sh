#!/bin/bash
# ~/.claude/claude-code-helper/scripts/record.sh
# Claude Code Monitor - Event Recording Script with terminal-notifier

set -euo pipefail

# 目录配置
CLAUDE_DIR="$HOME/.claude"
APP_DIR="$CLAUDE_DIR/claude-code-helper"
DB_PATH="$CLAUDE_DIR/monitor.db"          # 数据库放在 Claude 根目录
LOG_PATH="$APP_DIR/logs/monitor.log"
EVENT_TYPE="${1:-unknown}"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_PATH")"

# Read JSON input from stdin if available
if [ -t 0 ]; then
    # stdin is a terminal (manual execution)
    HOOK_INPUT=""
    MESSAGE="${2:-}"
    SESSION_ID_FROM_HOOK=""
    SOURCE_TYPE=""
else
    # stdin has data (hook execution from Claude Code)
    HOOK_INPUT=$(cat)
    # Try both 'prompt' (UserPromptSubmit) and 'message' (legacy) fields
    MESSAGE=$(echo "$HOOK_INPUT" | jq -r '.prompt // .message // ""' 2>/dev/null || echo "")
    SESSION_ID_FROM_HOOK=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")
    SOURCE_TYPE=$(echo "$HOOK_INPUT" | jq -r '.source // ""' 2>/dev/null || echo "")
fi

# Log function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_PATH"
}

# Generate session UUID
generate_uuid() {
    echo "$(date +%s)-$$-$RANDOM"
}

# Get project information
get_project_info() {
    PROJECT_PATH="$PWD"
    PROJECT_NAME=$(basename "$PROJECT_PATH")
    echo "$PROJECT_NAME|$PROJECT_PATH"
}

# Get terminal session information
get_terminal_session() {
    echo "${TERM_SESSION_ID:-unknown}"
}

# Get or create current session
get_or_create_session() {
    local session_id

    # Use session_id from hook if available
    if [ -n "$SESSION_ID_FROM_HOOK" ]; then
        # Find session by UUID
        session_id=$(sqlite3 "$DB_PATH" \
            "SELECT id FROM sessions WHERE session_uuid='$SESSION_ID_FROM_HOOK' LIMIT 1" 2>/dev/null || echo "")
    fi

    # If not found, find running session by parent PID (Claude Code main process)
    # Use PPID because hooks run in child processes, but share the same parent
    if [ -z "$session_id" ]; then
        session_id=$(sqlite3 "$DB_PATH" \
            "SELECT id FROM sessions WHERE status='running' AND pid=$PPID ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "")

        # Verify the process is still alive
        if [ -n "$session_id" ]; then
            local session_pid=$(sqlite3 "$DB_PATH" \
                "SELECT pid FROM sessions WHERE id=$session_id" 2>/dev/null || echo "")

            if [ -n "$session_pid" ]; then
                # Check if process exists
                if ! kill -0 "$session_pid" 2>/dev/null; then
                    log "Found dead session $session_id (PID=$session_pid), marking as terminated"
                    sqlite3 "$DB_PATH" << EOF
UPDATE sessions
SET status='terminated',
    end_time=datetime('now'),
    duration=CAST((julianday(datetime('now')) - julianday(start_time)) * 86400 AS INTEGER)
WHERE id=$session_id;
EOF
                    session_id=""
                fi
            fi
        fi
    fi

    if [ -z "$session_id" ]; then
        # Create new session
        log "No running session found, creating new session..."
        local uuid="${SESSION_ID_FROM_HOOK:-$(generate_uuid)}"
        local project_info=$(get_project_info)
        local project_name=$(echo "$project_info" | cut -d'|' -f1)
        local project_path=$(echo "$project_info" | cut -d'|' -f2)
        local terminal_session=$(get_terminal_session)

        log "UUID: $uuid, Project: $project_name, Path: $project_path, Terminal: $terminal_session"

        # Escape single quotes for SQL
        project_name="${project_name//\'/\'\'}"
        project_path="${project_path//\'/\'\'}"

        session_id=$(sqlite3 "$DB_PATH" << EOF
INSERT INTO sessions (session_uuid, start_time, status, project_name, project_path, pid, terminal_session)
VALUES ('$uuid', datetime('now'), 'running', '$project_name', '$project_path', $PPID, '$terminal_session');
SELECT last_insert_rowid();
EOF
)
        log "Created new session: $session_id (PPID: $PPID)"
    else
        log "Found existing session: $session_id"
    fi

    echo "$session_id"
}

# Record message
record_message() {
    local session_id=$1
    local content=$2

    if [ -n "$content" ]; then
        # Filter out system prompt messages that shouldn't be recorded
        # Skip messages like "Claude is waiting for your input"
        if [[ "$content" =~ "Claude is waiting for your input" ]]; then
            log "Skipped system prompt message: $content"
            return 0
        fi

        # Escape single quotes
        content="${content//\'/\'\'}"

        # Get project path from current directory
        local project_path="$PWD"
        project_path="${project_path//\'/\'\'}"

        # Don't calculate interaction_duration here - it will be updated when Stop event occurs
        sqlite3 "$DB_PATH" << EOF
INSERT INTO messages (session_id, message_type, content, interaction_duration, project_path)
VALUES (
    $session_id,
    'user',
    '$content',
    NULL,
    '$project_path'
);
EOF
        log "Recorded message for session $session_id (path: $project_path)"
    fi
}

# Record event
record_event() {
    local session_id=$1
    local event_type=$2
    local event_data=$3

    # Escape single quotes
    event_data="${event_data//\'/\'\'}"

    sqlite3 "$DB_PATH" << EOF
INSERT INTO events (session_id, event_type, event_data)
VALUES ($session_id, '$event_type', '$event_data');
EOF
    log "Recorded event: $event_type for session $session_id"
}

# Format duration as human-readable string
format_duration() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if [ $hours -gt 0 ]; then
        echo "${hours}小时${minutes}分钟"
    elif [ $minutes -gt 0 ]; then
        echo "${minutes}分${secs}秒"
    else
        echo "${secs}秒"
    fi
}

# Send notification using terminal-notifier
send_notification() {
    local title="$1"
    local message="$2"
    local sound="${3:-default}"

    terminal-notifier -title "$title" -message "$message" -sound "$sound" &
    log "Notification sent: $title - $message"
}

# Main event handling
case "$EVENT_TYPE" in
    start|SessionStart)
        log "========== SessionStart Hook Triggered =========="
        log "EVENT_TYPE: $EVENT_TYPE"
        log "SOURCE: $SOURCE_TYPE"
        log "SESSION_ID: $SESSION_ID_FROM_HOOK"
        log "PID: $$"

        SESSION_ID=$(get_or_create_session)
        log "SESSION_ID: $SESSION_ID"

        record_event "$SESSION_ID" "SessionStart" "{\"source\":\"$SOURCE_TYPE\"}"

        # Send start notification
        PROJECT=$(basename "$PWD")
        send_notification "🚀 Claude Code 启动" "项目: $PROJECT" "Blow"

        log "Session started: $SESSION_ID"
        log "=================================================="
        ;;

    stop|Stop)
        log "========== Stop Hook Triggered =========="
        log "EVENT_TYPE: $EVENT_TYPE"
        log "SESSION_ID: $SESSION_ID_FROM_HOOK"
        log "PID: $$"

        SESSION_ID=$(get_or_create_session)
        log "SESSION_ID: $SESSION_ID"

        record_event "$SESSION_ID" "Stop" "{}"

        # 计算单次对话耗时(从最后一次用户提问到现在)
        # 如果没有 last_prompt_time,则使用 start_time (兼容旧数据)
        LAST_PROMPT_TIME=$(sqlite3 "$DB_PATH" "SELECT last_prompt_time FROM sessions WHERE id=$SESSION_ID")

        if [ -n "$LAST_PROMPT_TIME" ] && [ "$LAST_PROMPT_TIME" != "" ]; then
            # 使用 last_prompt_time 计算单次对话耗时
            DURATION=$(sqlite3 "$DB_PATH" \
                "SELECT CAST((julianday(datetime('now')) - julianday('$LAST_PROMPT_TIME')) * 86400 AS INTEGER)")
            log "Calculated duration from last_prompt_time: $DURATION seconds"
        else
            # 回退到使用 start_time (用于没有 UserPromptSubmit 的情况)
            DURATION=$(sqlite3 "$DB_PATH" \
                "SELECT CAST((julianday(datetime('now')) - julianday(start_time)) * 86400 AS INTEGER) FROM sessions WHERE id=$SESSION_ID")
            log "Calculated duration from start_time (no prompt recorded): $DURATION seconds"
        fi

        # Update session end time and durations
        # duration: 会话总时长(从 start_time 到 now)
        # last_interaction_duration: 单次对话时长(用于通知和统计)
        sqlite3 "$DB_PATH" << EOF
UPDATE sessions
SET
    end_time = datetime('now'),
    duration = CAST((julianday(datetime('now')) - julianday(start_time)) * 86400 AS INTEGER),
    last_interaction_duration = $DURATION,
    status = 'completed'
WHERE id = $SESSION_ID;

-- Update the last message's interaction_duration with the actual duration
UPDATE messages
SET interaction_duration = $DURATION
WHERE id = (SELECT MAX(id) FROM messages WHERE session_id = $SESSION_ID);
EOF

        # Get session info for notification
        PROJECT=$(sqlite3 "$DB_PATH" "SELECT project_name FROM sessions WHERE id=$SESSION_ID")

        # Get today's stats
        TODAY_COUNT=$(sqlite3 "$DB_PATH" \
            "SELECT COUNT(*) FROM sessions WHERE date(start_time) = date('now', 'localtime') AND status='completed'")
        # 使用 last_interaction_duration 计算今日单次对话时长的平均值
        TODAY_AVG=$(sqlite3 "$DB_PATH" \
            "SELECT COALESCE(AVG(last_interaction_duration), 0) FROM sessions WHERE date(start_time) = date('now', 'localtime') AND status='completed' AND last_interaction_duration IS NOT NULL")

        # Format duration strings
        DURATION_STR=$(format_duration $DURATION)

        TODAY_AVG_INT=${TODAY_AVG%.*}
        if [ -z "$TODAY_AVG_INT" ] || [ "$TODAY_AVG_INT" = "0" ]; then
            AVG_STR="0秒"
        elif [ "$TODAY_AVG_INT" -lt 60 ]; then
            AVG_STR="${TODAY_AVG_INT}秒"
        else
            AVG_STR="$((TODAY_AVG_INT/60))分钟"
        fi

        # Send completion notification
        log "Sending completion notification for session $SESSION_ID"
        log "Project: $PROJECT, Duration: $DURATION_STR, Today: ${TODAY_COUNT}次, Avg: ${AVG_STR}"

        send_notification "✅ Claude Code 完成" \
            "项目: $PROJECT
耗时: $DURATION_STR
今日: 第${TODAY_COUNT}次, 平均${AVG_STR}" \
            "Glass"

        log "Session completed: $SESSION_ID, Duration: $DURATION seconds"
        log "=================================================="

        # Update statistics table
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
        log "EVENT_TYPE: $EVENT_TYPE"
        log "MESSAGE: $MESSAGE"
        log "PID: $$"

        SESSION_ID=$(get_or_create_session)
        log "SESSION_ID: $SESSION_ID"

        record_message "$SESSION_ID" "$MESSAGE"
        record_event "$SESSION_ID" "UserPromptSubmit" "{\"message\":\"$MESSAGE\"}"

        # 记录用户提问时间,用于计算单次对话耗时
        sqlite3 "$DB_PATH" << EOF
UPDATE sessions
SET last_prompt_time = datetime('now')
WHERE id = $SESSION_ID;
EOF

        log "User message recorded for session $SESSION_ID, prompt time updated"
        log "=================================================="
        ;;

    session_end|SessionEnd)
        log "========== SessionEnd Hook Triggered =========="
        log "EVENT_TYPE: $EVENT_TYPE"
        log "SESSION_ID: $SESSION_ID_FROM_HOOK"
        log "PID: $$"

        SESSION_ID=$(get_or_create_session)
        log "SESSION_ID: $SESSION_ID"

        record_event "$SESSION_ID" "SessionEnd" "{}"

        # 检查是否有 last_prompt_time (说明用户提交过问题)
        LAST_PROMPT_TIME=$(sqlite3 "$DB_PATH" "SELECT last_prompt_time FROM sessions WHERE id=$SESSION_ID")

        if [ -n "$LAST_PROMPT_TIME" ] && [ "$LAST_PROMPT_TIME" != "" ]; then
            # 用户提交过问题,计算耗时并发送通知
            DURATION=$(sqlite3 "$DB_PATH" \
                "SELECT CAST((julianday(datetime('now')) - julianday('$LAST_PROMPT_TIME')) * 86400 AS INTEGER)")
            log "Calculated duration from last_prompt_time: $DURATION seconds"

            # Update session and last message's interaction_duration
            sqlite3 "$DB_PATH" << EOF
UPDATE sessions
SET
    end_time = datetime('now'),
    duration = CAST((julianday(datetime('now')) - julianday(start_time)) * 86400 AS INTEGER),
    last_interaction_duration = $DURATION,
    status = 'completed'
WHERE id = $SESSION_ID;

-- Update the last message's interaction_duration with the actual duration
UPDATE messages
SET interaction_duration = $DURATION
WHERE id = (SELECT MAX(id) FROM messages WHERE session_id = $SESSION_ID);
EOF

            # Get session info
            PROJECT=$(sqlite3 "$DB_PATH" "SELECT project_name FROM sessions WHERE id=$SESSION_ID")

            # Get today's stats
            TODAY_COUNT=$(sqlite3 "$DB_PATH" \
                "SELECT COUNT(*) FROM sessions WHERE date(start_time) = date('now', 'localtime') AND status='completed'")
            TODAY_AVG=$(sqlite3 "$DB_PATH" \
                "SELECT COALESCE(AVG(duration), 0) FROM sessions WHERE date(start_time) = date('now', 'localtime') AND status='completed'")

            # Format duration
            DURATION_STR=$(format_duration $DURATION)

            TODAY_AVG_INT=${TODAY_AVG%.*}
            if [ -z "$TODAY_AVG_INT" ] || [ "$TODAY_AVG_INT" = "0" ]; then
                AVG_STR="0秒"
            elif [ "$TODAY_AVG_INT" -lt 60 ]; then
                AVG_STR="${TODAY_AVG_INT}秒"
            else
                AVG_STR="$((TODAY_AVG_INT/60))分钟"
            fi

            # Send notification
            log "Sending session end notification for session $SESSION_ID"
            log "Project: $PROJECT, Duration: $DURATION_STR, Today: ${TODAY_COUNT}次, Avg: ${AVG_STR}"

            send_notification "✅ Claude Code 完成" \
                "项目: $PROJECT
耗时: $DURATION_STR
今日: 第${TODAY_COUNT}次, 平均${AVG_STR}
(会话结束)" \
                "Glass"

            # Update statistics
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
        else
            # 没有提交问题,只标记会话结束,不发送通知
            log "No user prompt recorded, marking session as completed without notification"

            sqlite3 "$DB_PATH" << EOF
UPDATE sessions
SET
    end_time = datetime('now'),
    duration = CAST((julianday(datetime('now')) - julianday(start_time)) * 86400 AS INTEGER),
    status = 'completed'
WHERE id = $SESSION_ID;
EOF
        fi

        log "Session ended: $SESSION_ID"
        log "=================================================="
        ;;

    notification|Notification)
        log "========== Notification Hook Triggered =========="
        log "EVENT_TYPE: $EVENT_TYPE"
        log "MESSAGE: $MESSAGE"
        log "PID: $$"

        SESSION_ID=$(get_or_create_session)
        log "SESSION_ID: $SESSION_ID"

        # Only record permission requests, skip idle timeout notifications
        if [[ "$MESSAGE" =~ "permission" ]] || [[ "$MESSAGE" =~ "Permission" ]]; then
            # This is a permission request - record it
            record_event "$SESSION_ID" "PermissionRequest" "{\"message\":\"$MESSAGE\"}"
            log "Permission request recorded: $MESSAGE"
        elif [[ "$MESSAGE" =~ "Claude is waiting for your input" ]]; then
            # This is an idle timeout notification - skip it
            log "Skipped idle timeout notification (not a user action)"
        else
            # Other notification types - record as generic notification
            record_event "$SESSION_ID" "Notification" "{\"message\":\"$MESSAGE\"}"
            log "Notification recorded: $MESSAGE"
        fi

        log "=================================================="
        ;;

    error|Error)
        log "========== Error Hook Triggered =========="
        log "EVENT_TYPE: $EVENT_TYPE"
        log "MESSAGE: $MESSAGE"
        log "PID: $$"

        SESSION_ID=$(get_or_create_session)
        log "SESSION_ID: $SESSION_ID"

        # Escape single quotes for error message
        ESCAPED_MESSAGE="${MESSAGE//\'/\'\'}"

        record_event "$SESSION_ID" "Error" "{\"error\":\"$ESCAPED_MESSAGE\"}"

        # Mark session as terminated
        sqlite3 "$DB_PATH" << EOF
UPDATE sessions
SET
    end_time = datetime('now'),
    duration = CAST((julianday(datetime('now')) - julianday(start_time)) * 86400 AS INTEGER),
    status = 'terminated'
WHERE id = $SESSION_ID;
EOF

        log "Error recorded for session $SESSION_ID: $MESSAGE"
        log "=================================================="

        # Send error notification
        send_notification "❌ Claude Code 错误" "$MESSAGE" "Funk"
        ;;

    *)
        log "Unknown event type: $EVENT_TYPE"
        exit 1
        ;;
esac

exit 0
