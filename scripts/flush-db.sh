#!/bin/bash
# flush-db.sh
# Claude Code Monitor - Database Flush Script
#
# 功能：清空数据库并重新初始化表结构
# 用法：bash flush-db.sh
#
# ⚠️  警告：此操作会删除所有历史数据！

set -e

# 目录配置
CLAUDE_DIR="$HOME/.claude"
APP_DIR="$CLAUDE_DIR/claude-code-helper"
DB_PATH="$CLAUDE_DIR/monitor.db"
INIT_SCRIPT="$APP_DIR/scripts/init.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}⚠️  Database Flush - Warning${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}This operation will:${NC}"
echo -e "  1. Backup current database to timestamped file"
echo -e "  2. Delete all session history"
echo -e "  3. Delete all messages"
echo -e "  4. Delete all events"
echo -e "  5. Recreate database structure"
echo ""

# Check if database exists
if [ ! -f "$DB_PATH" ]; then
    echo -e "${BLUE}ℹ️  Database not found: $DB_PATH${NC}"
    echo -e "${BLUE}   Nothing to flush. Run './install.sh' to create database.${NC}"
    exit 0
fi

# Show database stats before flush
echo -e "${BLUE}Current database statistics:${NC}"
SESSIONS_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sessions;" 2>/dev/null || echo "0")
MESSAGES_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM messages;" 2>/dev/null || echo "0")
EVENTS_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM events;" 2>/dev/null || echo "0")
DB_SIZE=$(du -h "$DB_PATH" | cut -f1)

echo -e "  Sessions: ${YELLOW}$SESSIONS_COUNT${NC}"
echo -e "  Messages: ${YELLOW}$MESSAGES_COUNT${NC}"
echo -e "  Events: ${YELLOW}$EVENTS_COUNT${NC}"
echo -e "  Database size: ${YELLOW}$DB_SIZE${NC}"
echo ""

# Ask for confirmation
echo -e "${RED}Are you sure you want to flush the database?${NC}"
echo -e "${YELLOW}Type 'yes' to confirm, or anything else to cancel:${NC}"
read -r CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo -e "${GREEN}✓ Operation cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}Proceeding with database flush...${NC}"
echo ""

# Step 1: Create backup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$CLAUDE_DIR/monitor.db.backup.$TIMESTAMP"

echo -e "${YELLOW}1. Creating backup...${NC}"
cp "$DB_PATH" "$BACKUP_FILE"
echo -e "${GREEN}✓ Backup created: $BACKUP_FILE${NC}"
echo ""

# Step 2: Remove old database
echo -e "${YELLOW}2. Removing old database...${NC}"
rm -f "$DB_PATH"
echo -e "${GREEN}✓ Database removed${NC}"
echo ""

# Step 3: Recreate database structure
echo -e "${YELLOW}3. Recreating database structure...${NC}"

if [ -f "$INIT_SCRIPT" ]; then
    # Run init script
    bash "$INIT_SCRIPT"
    echo -e "${GREEN}✓ Database structure recreated${NC}"
else
    echo -e "${RED}❌ Error: init.sh not found at $INIT_SCRIPT${NC}"
    echo -e "${YELLOW}   Restoring from backup...${NC}"
    cp "$BACKUP_FILE" "$DB_PATH"
    echo -e "${GREEN}✓ Database restored from backup${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Database Flush Complete${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}Summary:${NC}"
echo -e "  ✓ Old data backed up to: $BACKUP_FILE"
echo -e "  ✓ Database flushed and recreated"
echo -e "  ✓ All tables, indexes, views, and triggers restored"
echo ""

echo -e "${BLUE}Backup information:${NC}"
echo -e "  Previous sessions: $SESSIONS_COUNT"
echo -e "  Previous messages: $MESSAGES_COUNT"
echo -e "  Previous events: $EVENTS_COUNT"
echo ""

echo -e "${YELLOW}Note:${NC}"
echo -e "  Your backup is safe at: ${BLUE}$BACKUP_FILE${NC}"
echo -e "  To restore, run: ${BLUE}cp $BACKUP_FILE $DB_PATH${NC}"
echo ""
