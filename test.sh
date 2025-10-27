#!/bin/bash
# test.sh
# Claude Code Monitor - Testing Script

set -e

CLAUDE_DIR="$HOME/.claude"
DB_PATH="$CLAUDE_DIR/monitor.db"
TEST_DB_PATH="$CLAUDE_DIR/test_monitor.db"
SCRIPTS_DIR="$CLAUDE_DIR/scripts"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Test result tracking
test_result() {
    local test_name=$1
    local result=$2

    TESTS_TOTAL=$((TESTS_TOTAL + 1))

    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}✓ PASS${NC} - $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC} - $test_name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Assertion functions
assert_equal() {
    local expected=$1
    local actual=$2
    local test_name=$3

    if [ "$expected" = "$actual" ]; then
        test_result "$test_name" 0
    else
        echo -e "  ${RED}Expected: $expected, Got: $actual${NC}"
        test_result "$test_name" 1
    fi
}

assert_not_empty() {
    local value=$1
    local test_name=$2

    if [ -n "$value" ]; then
        test_result "$test_name" 0
    else
        echo -e "  ${RED}Value is empty${NC}"
        test_result "$test_name" 1
    fi
}

assert_greater() {
    local value=$1
    local threshold=$2
    local test_name=$3

    if [ "$value" -gt "$threshold" ]; then
        test_result "$test_name" 0
    else
        echo -e "  ${RED}Value $value is not greater than $threshold${NC}"
        test_result "$test_name" 1
    fi
}

assert_file_exists() {
    local file=$1
    local test_name=$2

    if [ -f "$file" ]; then
        test_result "$test_name" 0
    else
        echo -e "  ${RED}File not found: $file${NC}"
        test_result "$test_name" 1
    fi
}

# Setup test environment
setup_test_env() {
    echo -e "${BLUE}Setting up test environment...${NC}"

    # Backup existing database if it exists
    if [ -f "$DB_PATH" ]; then
        cp "$DB_PATH" "${DB_PATH}.backup"
        echo -e "${YELLOW}  Backed up existing database${NC}"
    fi

    # Create test database
    cp "$DB_PATH" "$TEST_DB_PATH" 2>/dev/null || bash "$SCRIPTS_DIR/init.sh" > /dev/null
    cp "$CLAUDE_DIR/monitor.db" "$TEST_DB_PATH"

    echo -e "${GREEN}  Test environment ready${NC}"
    echo ""
}

# Cleanup test environment
cleanup_test_env() {
    echo ""
    echo -e "${BLUE}Cleaning up test environment...${NC}"

    # Remove test database
    rm -f "$TEST_DB_PATH"

    # Restore backup if it exists
    if [ -f "${DB_PATH}.backup" ]; then
        mv "${DB_PATH}.backup" "$DB_PATH"
        echo -e "${YELLOW}  Restored database backup${NC}"
    fi

    echo -e "${GREEN}  Cleanup complete${NC}"
}

# Test database connection
test_db_connection() {
    echo -e "${YELLOW}Testing database connection...${NC}"

    sqlite3 "$TEST_DB_PATH" "SELECT 1" &>/dev/null
    test_result "Database connection" $?
}

# Test table creation
test_table_creation() {
    echo -e "${YELLOW}Testing table creation...${NC}"

    local tables=$(sqlite3 "$TEST_DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;")

    echo "$tables" | grep -q "sessions"
    test_result "Sessions table exists" $?

    echo "$tables" | grep -q "messages"
    test_result "Messages table exists" $?

    echo "$tables" | grep -q "events"
    test_result "Events table exists" $?

    echo "$tables" | grep -q "statistics"
    test_result "Statistics table exists" $?
}

# Test index creation
test_index_creation() {
    echo -e "${YELLOW}Testing index creation...${NC}"

    local indexes=$(sqlite3 "$TEST_DB_PATH" "SELECT name FROM sqlite_master WHERE type='index';")

    echo "$indexes" | grep -q "idx_sessions_status_time"
    test_result "Status-time index exists" $?

    echo "$indexes" | grep -q "idx_sessions_project"
    test_result "Project index exists" $?

    echo "$indexes" | grep -q "idx_messages_session"
    test_result "Messages session index exists" $?
}

# Test view creation
test_view_creation() {
    echo -e "${YELLOW}Testing view creation...${NC}"

    local views=$(sqlite3 "$TEST_DB_PATH" "SELECT name FROM sqlite_master WHERE type='view';")

    echo "$views" | grep -q "active_sessions"
    test_result "Active sessions view exists" $?

    echo "$views" | grep -q "today_stats"
    test_result "Today stats view exists" $?
}

# Test session creation
test_session_creation() {
    echo -e "${YELLOW}Testing session creation...${NC}"

    # Insert test session
    sqlite3 "$TEST_DB_PATH" << EOF
INSERT INTO sessions (session_uuid, start_time, status, project_name, project_path, pid)
VALUES ('test-$(date +%s)', datetime('now'), 'running', 'test-project', '/tmp/test', 12345);
EOF

    local count=$(sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM sessions WHERE status='running';")
    assert_greater "$count" 0 "Session creation"
}

# Test message recording
test_message_recording() {
    echo -e "${YELLOW}Testing message recording...${NC}"

    # Get or create a session
    local session_id=$(sqlite3 "$TEST_DB_PATH" "SELECT id FROM sessions WHERE status='running' LIMIT 1;")

    if [ -z "$session_id" ]; then
        sqlite3 "$TEST_DB_PATH" "INSERT INTO sessions (session_uuid, start_time, status) VALUES ('test-msg', datetime('now'), 'running');"
        session_id=$(sqlite3 "$TEST_DB_PATH" "SELECT last_insert_rowid();")
    fi

    # Insert test message
    sqlite3 "$TEST_DB_PATH" << EOF
INSERT INTO messages (session_id, message_type, content)
VALUES ($session_id, 'user', 'Test message');
EOF

    local count=$(sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM messages WHERE session_id=$session_id;")
    assert_greater "$count" 0 "Message recording"
}

# Test special characters
test_special_characters() {
    echo -e "${YELLOW}Testing special character handling...${NC}"

    # Test single quote escaping
    local test_content="Test's message with 'quotes'"
    local escaped_content="${test_content//\'/\'\'}"

    local session_id=$(sqlite3 "$TEST_DB_PATH" "SELECT id FROM sessions LIMIT 1;")

    sqlite3 "$TEST_DB_PATH" << EOF
INSERT INTO messages (session_id, message_type, content)
VALUES ($session_id, 'user', '$escaped_content');
EOF

    test_result "Special character escaping" $?
}

# Test duration calculation
test_duration_calculation() {
    echo -e "${YELLOW}Testing duration calculation...${NC}"

    # Create a session with start and end time
    sqlite3 "$TEST_DB_PATH" << EOF
INSERT INTO sessions (session_uuid, start_time, end_time, status)
VALUES ('test-duration', datetime('now', '-1 hour'), datetime('now'), 'completed');

UPDATE sessions
SET duration = CAST((julianday(end_time) - julianday(start_time)) * 86400 AS INTEGER)
WHERE session_uuid = 'test-duration';
EOF

    local duration=$(sqlite3 "$TEST_DB_PATH" "SELECT duration FROM sessions WHERE session_uuid='test-duration';")

    # Duration should be approximately 3600 seconds (1 hour)
    if [ "$duration" -gt 3500 ] && [ "$duration" -lt 3700 ]; then
        test_result "Duration calculation" 0
    else
        echo -e "  ${RED}Duration $duration not in expected range (3500-3700)${NC}"
        test_result "Duration calculation" 1
    fi
}

# Test query scripts exist
test_script_files() {
    echo -e "${YELLOW}Testing script files...${NC}"

    assert_file_exists "$SCRIPTS_DIR/init.sh" "init.sh exists"
    assert_file_exists "$SCRIPTS_DIR/record.sh" "record.sh exists"
    assert_file_exists "$SCRIPTS_DIR/cleanup.sh" "cleanup.sh exists"
    assert_file_exists "$SCRIPTS_DIR/query.sh" "query.sh exists"
}

# Test script permissions
test_script_permissions() {
    echo -e "${YELLOW}Testing script permissions...${NC}"

    for script in init.sh record.sh cleanup.sh query.sh; do
        if [ -x "$SCRIPTS_DIR/$script" ]; then
            test_result "$script is executable" 0
        else
            test_result "$script is executable" 1
        fi
    done
}

# Main test execution
main() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Claude Code Monitor - Test Suite${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    setup_test_env

    # Run all tests
    test_db_connection
    echo ""

    test_table_creation
    echo ""

    test_index_creation
    echo ""

    test_view_creation
    echo ""

    test_session_creation
    echo ""

    test_message_recording
    echo ""

    test_special_characters
    echo ""

    test_duration_calculation
    echo ""

    test_script_files
    echo ""

    test_script_permissions
    echo ""

    cleanup_test_env

    # Print summary
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Test Summary${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Total tests: $TESTS_TOTAL"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✅ All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}❌ Some tests failed${NC}"
        exit 1
    fi
}

main "$@"
