# claude-minimalist-status-icon

A tiny Windows tray ring showing your Claude plan usage. One PowerShell file, nothing to install.

- **Ring** = current session (5-hour) usage
- **Water level** inside the ring = weekly usage, shown once it passes 50% (the ring gets thinner to make room)
- Each limit turns amber at 70% and red at 90% on its own; empty ring = no data (hover for why)
- Background ring adapts to the Windows light/dark theme
- Hover for percentages and reset times; right-click for details, refresh, exit, uninstall

## Install

Paste into PowerShell:

```powershell
irm https://raw.githubusercontent.com/VIPTrollik/claude-minimalist-status-icon/main/claude-tray.ps1 | iex
```

It copies itself to `%LOCALAPPDATA%\ClaudeStatusIcon`, adds a Startup shortcut and starts. Run the same command again to update.

**Uninstall:** right-click the icon → Uninstall.

## Settings

```powershell
& "$env:LOCALAPPDATA\ClaudeStatusIcon\claude-tray.ps1" -Layout water -Warn on -HideWeeklyBelow 50
```

| Option | Values | Default |
|---|---|---|
| `-Layout` | `water` (session ring + weekly water level) or `ring` (session only) | `water` |
| `-Warn` | `on` / `off`: amber at 70%, red at 90%, per limit | `on` |
| `-HideWeeklyBelow` | `0`–`100`: hide the water level while weekly is below this (`0` = always show) | `50` |
| `-Color` | session ring colour | `#3BA8EA` |
| `-WeeklyColor` | weekly water level colour | `#A78BFA` |
| `-Track` | background ring colour | follows Windows theme |

Colours are `#RRGGBB`, `#RRGGBBAA` (alpha last) or a name like `white`. Pass any subset; `-Reset` restores defaults. The icon restarts with the new settings, and updates keep them.
## Requirements

Windows 10/11 and the [Claude Code](https://claude.com/claude-code) CLI signed in once with a Pro/Max account (`claude auth login`). The script reads the login from `~/.claude/.credentials.json` and polls the same usage endpoint `/usage` uses (undocumented, may change) every 3 minutes.

When the access token expires, the script refreshes it the way Claude Code does and writes the new tokens back to that file, so it keeps working even if you only use the desktop app. If the login itself is revoked, the ring empties and the tooltip says to run `claude auth login`. Brief network errors keep the last values, marked as stale.
