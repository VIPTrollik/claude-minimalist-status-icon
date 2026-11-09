# claude-minimalist-status-icon

A tiny Windows tray ring showing your Claude plan usage. One PowerShell file, nothing to install.

- **Ring** = current session (5-hour) usage
- **Center dot** = weekly usage level
- Blue < 70% · amber < 90% · red ≥ 90% · grey = no data (hover for why)
- Hover for percentages and reset times; right-click for details, refresh, exit, uninstall

## Install

Paste into PowerShell:

```powershell
irm https://raw.githubusercontent.com/VIPTrollik/claude-minimalist-status-icon/main/claude-tray.ps1 | iex
```

It copies itself to `%LOCALAPPDATA%\ClaudeStatusIcon`, adds a Startup shortcut and starts. Run the same command again to update.

**Uninstall:** right-click the icon → Uninstall.

## Requirements

Windows 10/11 and [Claude Code](https://claude.com/claude-code) signed in with a Pro/Max account. The script reads Claude Code's token from `~/.claude/.credentials.json` and polls the same usage endpoint `/usage` uses (undocumented, may change) every 3 minutes. If the token expires, the ring turns grey until you next use Claude Code.
