# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Communication Guidelines

**IMPORTANT: 与用户沟通时必须使用简体中文。**

所有回复、说明、错误消息和交互内容都应该使用简体中文,除非:
- 代码注释需要使用英文(如果项目规范要求)
- 技术术语没有合适的中文翻译
- 用户明确要求使用英文

## Project Overview

Claude Code Helper is a lightweight monitoring tool for Claude Code sessions that tracks execution time, records conversation history, and provides system notifications when tasks complete. The system uses Claude Hooks (official Claude Code extension mechanism), SQLite database, and shell scripts to achieve zero-intrusion monitoring.

**Core Features:**
- Session lifecycle tracking (start/stop/duration)
- User message recording for history
- macOS notification alerts on completion
- SQLite-based data persistence
- Statistical analysis and reporting
- Automatic cleanup of abnormal sessions (daemon-based)

## Architecture Overview

The system uses a **4-layer architecture** with event-driven processing:

1. **Hook Layer**: Claude Code hooks intercept lifecycle events (SessionStart/Stop/Notification/Error) and trigger shell scripts with JSON payloads via stdin
2. **Script Layer**: Bash scripts (`record.sh`, `cleanup.sh`, `query.sh`) handle events and data operations
3. **Data Layer**: SQLite database (`~/.claude/monitor.db`) with 4 tables, 5 indexes, 2 views, and triggers for data integrity
4. **Notification Layer**: macOS native notifications via `osascript` (dialog-based for reliability) or `terminal-notifier`

### Data Flow

```
Claude Code Event → Hook Trigger → record.sh (stdin JSON) → SQLite Write → Notification
                                                                    ↓
                                                           Daemon (cleanup.sh)
                                                                    ↓
                                                           Mark Terminated Sessions
```

### Database Schema

**Tables:**
- `sessions` - Core session tracking (uuid, times, duration, status, project info, pid, terminal_session)
- `messages` - User messages linked to sessions (FK cascade delete)
- `events` - Hook event logging with JSON event_data
- `statistics` - Daily aggregated metrics (auto-updated via SQL on Stop event)

**Views:**
- `active_sessions` - Running sessions filtered by status='running'
- `today_stats` - Real-time today's aggregated statistics

**Key Indexes:** status+start_time, project_name, session_id (messages/events), date (statistics)

## Development Commands

### Installation & Setup

```bash
# Standard installation (copies scripts, initializes DB, configures hooks)
./install.sh

# Install with daemon for automatic cleanup (recommended)
./install.sh --with-daemon

# Uninstall (prompts to keep data)
./uninstall.sh

# Run tests (database integrity, script permissions, session lifecycle)
./test.sh
```

### Common Development Tasks

```bash
# Query operations (use aliases after installation)
claude-stats                    # View statistics
claude-today                    # View today's sessions
claude-query active             # View running sessions
claude-query messages [id]      # View messages for session
claude-query export csv         # Export data as CSV
claude-query clean 30           # Clean data older than 30 days

# Direct database access
sqlite3 ~/.claude/monitor.db
# Example queries:
#   SELECT * FROM active_sessions;
#   SELECT * FROM today_stats;
#   SELECT * FROM sessions WHERE status='terminated';

# Manual hook testing (for debugging)
echo '{"message":"test"}' | ~/.claude/scripts/record.sh start
~/.claude/scripts/record.sh stop

# Daemon management
launchctl load ~/Library/LaunchAgents/com.claude.monitor.plist
launchctl unload ~/Library/LaunchAgents/com.claude.monitor.plist
launchctl list | grep claude.monitor

# View logs
tail -f ~/.claude/logs/monitor.log
tail -f ~/.claude/logs/daemon.log
```

### Testing & Debugging

```bash
# Run full test suite (23 tests)
./test.sh

# Test individual hooks with input
echo '{"message":"test","source":"user"}' | bash -x ~/.claude/scripts/record.sh start

# Diagnose hooks configuration
./diagnose_hooks.sh

# Manual cleanup trigger
~/.claude/scripts/cleanup.sh

# Check database integrity
sqlite3 ~/.claude/monitor.db "PRAGMA integrity_check;"
```

## Implementation Guidelines

### Hook Execution Model

**Critical:** Hooks receive JSON via stdin and must complete in <50ms to avoid blocking Claude Code.

**Input Format (stdin):**
```json
{
  "message": "User's message text",
  "session_id": "claude-session-uuid",
  "source": "user|system|resume"
}
```

**Hook Processing Flow:**
1. `record.sh` reads JSON from stdin using `cat` (if stdin is not a terminal)
2. Extracts fields using `jq` (message, session_id, source)
3. Finds or creates running session in database (last running session by DESC id)
4. Performs SQL operations (insert/update) with escaped strings (`'` → `''`)
5. For Stop event: triggers notification with formatted stats
6. Logs all operations to `~/.claude/logs/monitor.log` with timestamps

### Session State Machine

```
[Start Hook] → running → [Stop Hook] → completed
                ↓
           [Ctrl+C / Terminal Close] → running (orphaned)
                ↓
           [Daemon cleanup.sh] → terminated
```

**Key Behaviors:**
- **One active session per terminal**: Uses latest `status='running'` record
- **Session UUID**: Generated as `$(date +%s)-$$-$RANDOM` (timestamp-pid-random)
- **PID tracking**: Used by cleanup script to detect orphaned sessions via `kill -0 $pid`
- **24-hour timeout**: Sessions running >24h automatically marked terminated

### SQL Injection Protection

**ALL user input must be escaped before SQL insertion:**

```bash
# Correct escaping in record.sh
content="${content//\'/\'\'}"  # Replace ' with ''
sqlite3 "$DB_PATH" << EOF
INSERT INTO messages (content) VALUES ('$content');
EOF
```

**Never:** Directly interpolate user input into SQL without escaping single quotes.

### Notification Strategy

Uses `osascript display dialog` instead of `display notification` for reliability:
- **Dialog advantages**: Guaranteed to appear, user-dismissible, survives sleep/wake
- **5-second auto-dismiss**: `giving up after 5` parameter
- **Format:** "项目: {name} / 耗时: {duration} / 今日: 第{N}次, 平均{avg}"
- **Duration formatting:** <60s: "Ns", <3600s: "Nm Ns", else: "Nh Nm"

### Database Operations

**Session Creation (SessionStart):**
```sql
INSERT INTO sessions (session_uuid, start_time, status, project_name, project_path, pid, terminal_session)
VALUES ('uuid', datetime('now'), 'running', 'name', 'path', pid, '$TERM_SESSION_ID');
```

**Session Completion (Stop):**
```sql
UPDATE sessions SET
  end_time = datetime('now'),
  duration = CAST((julianday(datetime('now')) - julianday(start_time)) * 86400 AS INTEGER),
  status = 'completed'
WHERE id = $SESSION_ID;
```

**Statistics Update (Stop):**
```sql
INSERT OR REPLACE INTO statistics (date, total_sessions, total_duration, avg_duration, completed_count)
SELECT date('now', 'localtime'), COUNT(*), SUM(duration), AVG(duration),
       COUNT(CASE WHEN status='completed' THEN 1 END)
FROM sessions WHERE date(start_time) = date('now', 'localtime');
```

### Cleanup Process (cleanup.sh)

Runs every 5 minutes via LaunchAgent:
1. Query all running sessions: `SELECT id, pid FROM sessions WHERE status='running'`
2. For each session: check if process exists with `kill -0 $pid 2>/dev/null`
3. If process dead: mark as terminated and set end_time
4. Check for sessions running >24h: mark as terminated
5. Execute `VACUUM` to reclaim space from deleted records

### File Structure

```
Project Root (development):
├── install.sh              # Main installer with Python hook config
├── uninstall.sh           # Removes hooks, daemon, optionally data
├── test.sh                # 23-test suite
└── scripts/
    ├── init.sh           # Creates DB schema (tables/indexes/views/triggers)
    ├── record.sh         # Hook handler (start/stop/notification/error)
    └── query.sh          # CLI for stats/export/clean operations

Runtime (~/.claude/):
├── settings.json                   # Claude Code config (hooks added by install.sh, shared)
└── claude-code-helper/            # Our application directory (isolated, can be safely deleted)
    ├── monitor.db                 # SQLite database (persistent)
    ├── scripts/                   # Copied from project during install
    │   ├── init.sh
    │   ├── record.sh
    │   └── query.sh
    ├── logs/                      # monitor.log, daemon.log, daemon_error.log
    └── backups/                   # Manual backup destination
```

## Key Technical Decisions & Constraints

### Design Choices
1. **SQLite over Files**: ACID guarantees, SQL queries, efficient indexing, <10ms query time
2. **Shell Scripts over Python**: Minimal dependencies (bash, sqlite3, jq), fast startup (<50ms), easier distribution
3. **Hook-Based Architecture**: Non-invasive, officially supported by Claude Code, event-driven
4. **Dialog over Notification**: `display dialog` more reliable than `display notification` (survives sleep/wake)
5. **Local-Only Storage**: Privacy-first, all data stays on user's machine
6. **Session UUID Format**: `$(date +%s)-$$-$RANDOM` ensures uniqueness across terminals
7. **Latest Session Strategy**: Assumes one active session per terminal, queries `ORDER BY id DESC LIMIT 1`
8. **Directory Isolation Principle**: ⚠️ **CRITICAL** - Clean separation of concerns!
   - **Application Directory**: `~/.claude/claude-code-helper/` (our exclusive space)
     - Contains: `monitor.db`, `scripts/`, `logs/`, `backups/`
     - **Safe to delete entirely** on uninstall - no risk to other tools
     - Clear ownership and isolation
   - **Shared File**: `~/.claude/settings.json` (Claude Code official config)
     - **NEVER** delete this file - only modify the `hooks` field
     - Always backup before modification (with timestamp)
     - On uninstall: remove our hooks, preserve everything else
   - **Uninstall Strategy**: Simply `rm -rf ~/.claude/claude-code-helper`
   - **Benefits**: No conflicts, easy cleanup, clear boundaries

### Performance Constraints
- **Hook execution**: <50ms total (critical path)
- **Database queries**: <10ms per operation (indexed queries only)
- **Notification delay**: <100ms target
- **Daemon interval**: 5 minutes (balance between responsiveness and CPU usage)

### Security Requirements
- **SQL injection prevention**: ALL user input must be escaped (`'` → `''`)
- **No sensitive data**: Don't store API keys, tokens, or credentials in messages
- **File permissions**: Scripts should be 755, database 644, logs 644

### Platform Limitations
Current implementation is **macOS-only**:
- **Notifications**: Uses `osascript` (macOS AppleScript)
- **Terminal detection**: Uses `$TERM_SESSION_ID` (macOS Terminal.app)
- **Daemon**: Uses LaunchAgent plist (macOS service management)

For **Linux port**, replace:
- Notifications: `notify-send` or `zenity`
- Terminal detection: `$WINDOWID` or `$DISPLAY`
- Daemon: systemd timer unit

For **Windows port**, replace:
- Notifications: PowerShell `New-BurntToastNotification` or Windows API
- Terminal detection: `$PID` + parent process name
- Daemon: Task Scheduler

## Testing & Validation

### Test Coverage (test.sh)
The test suite validates:
1. **Database**: Connection, table creation, indexes, views, triggers
2. **Sessions**: Creation, status transitions, duration calculation
3. **Messages**: Recording, special character escaping (single quotes)
4. **Scripts**: File existence, executable permissions
5. **Integration**: Session lifecycle (start → stop → cleanup)

**Run tests before committing changes:**
```bash
./test.sh  # Must pass 23/23 tests
```

### Manual Testing Scenarios
1. **Normal flow**: Start Claude → run task → stop → verify notification + completed status
2. **Abnormal exit**: Start Claude → Ctrl+C → wait 5 min → verify terminated status
3. **Terminal close**: Start Claude → close terminal → wait 5 min → verify terminated status
4. **Concurrent sessions**: Multiple terminals running simultaneously → each tracked separately
5. **Special characters**: Send message with quotes/apostrophes → verify correct storage

### Debugging Tips
- **Hooks not firing**: Check `~/.claude/settings.json` has correct hooks config
- **No notifications**: Test `osascript -e 'display dialog "test"'` directly
- **Session not ending**: Check daemon is running with `launchctl list | grep claude.monitor`
- **Database locked**: Check for concurrent access with `lsof ~/.claude/monitor.db`
- **Hook failures**: Check logs at `~/.claude/logs/monitor.log` for errors

## Modifying the System

### Adding New Event Types
1. Add handler case in `record.sh` (lines 134-288)
2. Update hook config in `install.sh` (lines 222-257)
3. Add event_type to events table if needed
4. Update tests in `test.sh`

### Adding New Query Commands
1. Add command case in `query.sh`
2. Write SQL query using indexed columns
3. Format output for readability
4. Update `claude-query help` output
5. Add alias to `install.sh` if frequently used

### Changing Notification Format
Edit `record.sh` lines 211-213 (Stop event notification):
- Modify dialog text format
- Adjust `giving up after N` timeout
- Change icon (note/caution/stop)
- Add sound with `beep` parameter

### Database Schema Changes
1. Create migration script (e.g., `migrate_v1_to_v2.sh`)
2. Update `init.sh` with new schema
3. Test migration on backup database
4. Update queries in `record.sh` and `query.sh`
5. Bump version in documentation

## Troubleshooting Common Issues

### Issue: Hooks not executing
**Symptoms:** No sessions being recorded
**Diagnosis:**
```bash
# Check hooks config
cat ~/.claude/settings.json | jq '.hooks'

# Test hook manually
echo '{"message":"test"}' | bash -x ~/.claude/scripts/record.sh start

# Check script permissions
ls -l ~/.claude/scripts/*.sh
```
**Fix:** Re-run `./install.sh` or manually add hooks to settings.json

### Issue: Database is locked
**Symptoms:** `Error: database is locked` in logs
**Diagnosis:**
```bash
lsof ~/.claude/monitor.db
```
**Fix:** Close open sqlite3 sessions, restart daemon

### Issue: Daemon not running
**Symptoms:** Orphaned sessions not cleaned up
**Diagnosis:**
```bash
launchctl list | grep claude.monitor
tail ~/.claude/logs/daemon_error.log
```
**Fix:**
```bash
launchctl unload ~/Library/LaunchAgents/com.claude.monitor.plist
launchctl load ~/Library/LaunchAgents/com.claude.monitor.plist
```

### Issue: Notifications not showing
**Symptoms:** No dialog appears on Stop event
**Diagnosis:**
```bash
# Test osascript directly
osascript -e 'display dialog "test"'

# Check System Preferences → Notifications → Terminal
```
**Fix:** Enable notifications for Terminal.app in System Preferences
