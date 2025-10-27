# Claude Code Monitor

A lightweight session monitoring tool for Claude Code that tracks execution time, records conversation history, and provides desktop notifications when tasks complete.

## ✨ Features

- **📊 Session Tracking**: Automatically tracks Claude Code sessions from start to finish
- **💬 Message Recording**: Records all user messages with session context
- **🔔 Smart Notifications**: Desktop notifications when tasks complete with duration stats
- **📈 Statistics & Analytics**: Daily/weekly statistics and session history
- **🗄️ SQLite Database**: Efficient local storage with full SQL query support
- **🔍 Powerful Queries**: CLI commands to view sessions, messages, and statistics
- **🛡️ Safe Uninstall**: Automatic database backup before uninstallation
- **🎯 Zero Intrusion**: Uses official Claude Code Hooks API

## 🎯 Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/claude-code-helper.git
cd claude-code-helper

# Run installation script
./install.sh
```

The installer will:
1. Copy scripts to `~/.claude/claude-code-helper/`
2. Create database at `~/.claude/monitor.db`
3. Configure Claude Code hooks automatically
4. Add convenient shell aliases

### First Use

After installation:

1. **Restart Claude Code** to activate hooks
2. **Reload your shell**:
   ```bash
   source ~/.zshrc  # or ~/.bashrc
   ```
3. **Test the installation**:
   ```bash
   claude-stats  # View statistics
   claude-today  # View today's sessions
   ```

## 📖 Usage

### Available Commands

```bash
# View today's sessions
claude-today

# View statistics
claude-stats

# View recent messages (default: 20)
claude-msg

# View specific message details
claude-msg <message_id>

# View all available commands
claude-query help
```

### Query Examples

```bash
# View active sessions
claude-query active

# View this week's sessions
claude-query week

# Export data as CSV
claude-query export csv

# Export data as JSON
claude-query export json

# Clean old data (older than 30 days)
claude-query clean 30
```

## 📊 Database Schema

The system uses SQLite with the following structure:

### Tables

- **sessions**: Session metadata (start/end time, duration, status, project)
- **messages**: User messages linked to sessions
- **events**: Hook event logs
- **statistics**: Daily aggregated metrics

### Views

- **active_sessions**: Currently running sessions
- **today_stats**: Real-time statistics for today

## 🗂️ Directory Structure

```
~/.claude/
├── settings.json              # Claude Code config (shared)
├── monitor.db                 # SQLite database
└── claude-code-helper/        # App directory (isolated)
    ├── scripts/               # Core scripts
    ├── logs/                  # Log files
    └── backups/               # Manual backups
```

**Design Benefits**:
- ✅ Clear isolation: All app files in subdirectory
- ✅ Safe uninstall: Remove app directory without affecting other tools
- ✅ Database in main directory for easy access
- ✅ Auto-backup on uninstall with timestamp

## 🔄 Uninstallation

```bash
./uninstall.sh
```

The uninstaller will:
1. **Backup database** to `~/.claude/monitor.db.backup.TIMESTAMP`
2. Remove database file
3. Remove application directory
4. Clean up hooks from settings.json
5. Remove shell aliases

**What's preserved**:
- `~/.claude/` directory (official Claude Code directory)
- Database backup with timestamp
- Other tools' data

## 🛠️ Requirements

- macOS 10.15+
- Bash 3.2+
- SQLite 3.x
- Claude Code (latest version)
- Python 3.x (for hooks configuration)

### Optional

- `terminal-notifier` for better notifications:
  ```bash
  brew install terminal-notifier
  ```

## 📋 Example Output

### Today's Sessions

```
=== Today's Sessions ===
Start     Duration  Status      Project
--------  --------  ----------  --------------------
14:08     35s       completed   claude-code-helper
13:45     2m15s     completed   my-project
```

### Recent Messages

```
=== Recent Messages (with session info) ===
ID  Project          Session Start  Duration  Status     Message
--  ---------------  -------------  --------  ---------  --------------------------------
5   my-project       10-27 15:46    7m        completed  Help me optimize the database
4   my-project       10-27 15:46    7m        completed  Show me the current schema
```

### Statistics

```
=== Statistics ===
Today's sessions:      5
Completed today:       4
Total time today:      1.5 hours
Average duration:      18 minutes
This week's sessions:  23
```

## 🐛 Troubleshooting

### Hooks not firing

Check hooks configuration:
```bash
cat ~/.claude/settings.json | python3 -m json.tool | grep -A 5 "hooks"
```

View logs:
```bash
tail -f ~/.claude/claude-code-helper/logs/monitor.log
```

### Notifications not showing

1. Check System Preferences → Notifications → Terminal
2. Install terminal-notifier: `brew install terminal-notifier`

### Database issues

```bash
# Check database integrity
sqlite3 ~/.claude/monitor.db "PRAGMA integrity_check;"

# View tables
sqlite3 ~/.claude/monitor.db ".tables"

# Backup manually
cp ~/.claude/monitor.db ~/.claude/backups/monitor.db.manual
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

MIT License - feel free to use this tool for personal or commercial projects.

## 🙏 Acknowledgments

- Built for [Claude Code](https://claude.ai/code) by Anthropic
- Uses official Claude Code Hooks API
- Inspired by the need for better session tracking and analytics

---

**Note**: This tool stores all data locally on your machine. No data is sent to external servers.
