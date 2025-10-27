#!/bin/bash
# ~/.claude/claude-code-helper/scripts/query.sh
# Claude Code Monitor - Query Tool

set -euo pipefail

# 目录配置
CLAUDE_DIR="$HOME/.claude"
APP_DIR="$CLAUDE_DIR/claude-code-helper"
DB_PATH="$CLAUDE_DIR/monitor.db"          # 数据库放在 Claude 根目录
COMMAND="${1:-help}"

# Colors
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
        MESSAGE_ID="${2:-}"
        if [ -z "$MESSAGE_ID" ]; then
            # Show recent messages (default: 20)
            LIMIT="${3:-20}"
            echo -e "${BLUE}=== 最近 $LIMIT 条消息 ===${NC}"
            sqlite3 "$DB_PATH" -column -header << EOF
.width 5 20 70
SELECT
    m.id as "ID",
    strftime('%Y-%m-%d %H:%M', m.timestamp) as "时间",
    substr(m.content, 1, 70) as "消息"
FROM messages m
JOIN sessions s ON m.session_id = s.id
ORDER BY m.timestamp DESC
LIMIT $LIMIT;
EOF
        else
            # Show specific message by ID (full content)
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${BLUE}📝 消息详情 #$MESSAGE_ID${NC}"
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

            # Get message details - query separately to avoid delimiter issues
            MSG_TIME=$(sqlite3 "$DB_PATH" "SELECT strftime('%Y-%m-%d %H:%M:%S', m.timestamp, 'localtime') FROM messages m WHERE m.id = $MESSAGE_ID;")
            MSG_CONTENT=$(sqlite3 "$DB_PATH" "SELECT m.content FROM messages m WHERE m.id = $MESSAGE_ID;")
            SESSION_ID=$(sqlite3 "$DB_PATH" "SELECT m.session_id FROM messages m WHERE m.id = $MESSAGE_ID;")
            PROJECT=$(sqlite3 "$DB_PATH" "SELECT s.project_name FROM messages m JOIN sessions s ON m.session_id = s.id WHERE m.id = $MESSAGE_ID;")
            STATUS=$(sqlite3 "$DB_PATH" "SELECT s.status FROM messages m JOIN sessions s ON m.session_id = s.id WHERE m.id = $MESSAGE_ID;")

            if [ -z "$MSG_TIME" ]; then
                echo -e "${RED}❌ 未找到消息 ID: $MESSAGE_ID${NC}"
            else

                echo ""
                echo -e "${GREEN}⏰ 时间：${NC}$MSG_TIME"
                echo -e "${GREEN}📂 项目：${NC}$PROJECT"
                echo -e "${GREEN}🔗 会话ID：${NC}$SESSION_ID ${YELLOW}(状态: $STATUS)${NC}"
                echo ""
                echo -e "${YELLOW}💬 完整内容：${NC}"
                echo -e "${BLUE}┌─────────────────────────────────────────────────────────────────────────────${NC}"
                # 使用 fold 将长文本自动换行（每行 75 字符）
                echo "$MSG_CONTENT" | fold -s -w 75 | while IFS= read -r line; do
                    echo -e "${BLUE}│${NC} $line"
                done
                echo -e "${BLUE}└─────────────────────────────────────────────────────────────────────────────${NC}"
                echo ""
            fi
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
            # Check if jq is available
            if command -v jq &> /dev/null; then
                sqlite3 "$DB_PATH" << EOF | jq '.' > "$OUTPUT_FILE"
SELECT json_group_array(json_object(
    'id', id,
    'session_uuid', session_uuid,
    'start_time', start_time,
    'end_time', end_time,
    'duration', duration,
    'status', status,
    'project_name', project_name,
    'project_path', project_path
))
FROM sessions;
EOF
                echo -e "${GREEN}✅ Exported to: $OUTPUT_FILE${NC}"
            else
                # Fallback without jq
                sqlite3 "$DB_PATH" << EOF > "$OUTPUT_FILE"
SELECT json_group_array(json_object(
    'id', id,
    'session_uuid', session_uuid,
    'start_time', start_time,
    'end_time', end_time,
    'duration', duration,
    'status', status,
    'project_name', project_name,
    'project_path', project_path
))
FROM sessions;
EOF
                echo -e "${GREEN}✅ Exported to: $OUTPUT_FILE${NC}"
                echo -e "${YELLOW}ℹ️  Note: Install jq for formatted JSON output${NC}"
            fi
        else
            echo -e "${RED}❌ Unknown format: $FORMAT${NC}"
            echo "Supported formats: csv, json"
            exit 1
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
        echo "  ${GREEN}today${NC}              - Show today's sessions"
        echo "  ${GREEN}stats${NC}              - Show statistics"
        echo "  ${GREEN}active${NC}             - Show active/running sessions"
        echo "  ${GREEN}messages${NC} [id]      - Show recent messages or details by message ID"
        echo "  ${GREEN}export${NC} [csv|json]  - Export data"
        echo "  ${GREEN}clean${NC} [days]       - Clean old data (default: 30 days)"
        echo "  ${GREEN}help${NC}               - Show this help"
        echo ""
        echo "Examples:"
        echo "  $0 today"
        echo "  $0 stats"
        echo "  $0 messages              # Show last 20 messages"
        echo "  $0 messages 9            # Show full content of message ID 9"
        echo "  $0 export csv"
        echo "  $0 clean 90"
        echo ""
        echo "Shortcuts:"
        echo "  ${GREEN}claude-msg${NC}         - Alias for 'messages' command"
        ;;
esac
