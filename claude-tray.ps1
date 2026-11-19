# Claude minimalist status icon - a tray ring showing your Claude plan usage.
# https://github.com/VIPTrollik/claude-minimalist-status-icon
#
#   Install / update :  irm https://raw.githubusercontent.com/VIPTrollik/claude-minimalist-status-icon/main/claude-tray.ps1 | iex
#   Uninstall        :  tray icon > right-click > Uninstall
#   Settings         :  & "$env:LOCALAPPDATA\ClaudeStatusIcon\claude-tray.ps1" -Layout water -Warn on -HideWeeklyBelow 50
#                       -Layout ring|water ring = session only, water = session ring + weekly water level inside
#                       -Warn on|off       each limit turns amber at 70% and red at 90%
#                       -HideWeeklyBelow N hide the weekly level while weekly usage is under N% (0 = always show)
#                       -Color / -WeeklyColor / -Track   colours (#RRGGBB, #RRGGBBAA or names like white)
#                       -Reset             back to defaults
#
# Run from anywhere except the install folder -> installs itself (copy, startup shortcut, launch).
# Run from the install folder (what the startup shortcut does) -> shows the tray icon.
# No Validate* attributes here: under `irm | iex` they are checked against the empty defaults
# and abort the install. Values are validated in Set-CsiConfig instead.
param(
    [switch]$Uninstall, [switch]$Run, [switch]$Reset,
    [string]$Layout, [string]$Warn, [int]$HideWeeklyBelow = -1,
    [string]$Color, [string]$WeeklyColor, [string]$Track
)

$CsiApp = @{
    Name     = 'ClaudeStatusIcon'
    Source   = 'https://raw.githubusercontent.com/VIPTrollik/claude-minimalist-status-icon/main/claude-tray.ps1'
    Dir      = Join-Path $env:LOCALAPPDATA 'ClaudeStatusIcon'
    Script   = Join-Path $env:LOCALAPPDATA 'ClaudeStatusIcon\claude-tray.ps1'
    Config   = Join-Path $env:LOCALAPPDATA 'ClaudeStatusIcon\config.json'
    Shortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'ClaudeStatusIcon.lnk'
}

# ---------------------------------------------------------------- colours / config

function ConvertTo-CsiColor([string]$value) {
    Add-Type -AssemblyName System.Drawing
    $v = $value.Trim()
    if ($v -match '^#?([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$') {
        $rgb = [Convert]::ToInt32($Matches[1], 16)
        $a = if ($Matches[2]) { [Convert]::ToInt32($Matches[2], 16) } else { 255 }
        return [Drawing.Color]::FromArgb($a, ($rgb -shr 16) -band 255, ($rgb -shr 8) -band 255, $rgb -band 255)
    }
    $named = [Drawing.Color]::FromName($v)
    if ($named.IsKnownColor) { return $named }
    throw "Unknown colour '$value' - use #RRGGBB, #RRGGBBAA (alpha last) or a name like white"
}

function Get-CsiConfig {
    $cfg = @{}
    if (Test-Path $CsiApp.Config) {
        (Get-Content $CsiApp.Config -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $cfg[$_.Name] = $_.Value }
    }
    return $cfg
}

function Set-CsiConfig {
    if (-not (Test-Path $CsiApp.Script)) { Write-Host 'Install the icon first.'; return }
    if ($Layout -eq 'pie') { $Layout = 'water' }   # old name
    if ($Layout -and $Layout -notin 'ring', 'water') { Write-Host "-Layout must be 'ring' or 'water'"; return }
    if ($Warn -and $Warn -notin 'on', 'off') { Write-Host "-Warn must be 'on' or 'off'"; return }
    if ($HideWeeklyBelow -gt 100) { Write-Host '-HideWeeklyBelow must be 0-100'; return }
    $cfg = if ($Reset) { @{} } else { Get-CsiConfig }
    if ($Layout) { $cfg.Layout = $Layout.ToLower() }
    if ($Warn) { $cfg.Warn = $Warn.ToLower() }
    if ($HideWeeklyBelow -ge 0) { $cfg.HideWeeklyBelow = $HideWeeklyBelow }
    if ($Color) { [void](ConvertTo-CsiColor $Color); $cfg.Color = $Color }
    if ($WeeklyColor) { [void](ConvertTo-CsiColor $WeeklyColor); $cfg.WeeklyColor = $WeeklyColor }
    if ($Track) { [void](ConvertTo-CsiColor $Track); $cfg.Track = $Track }
    if ($cfg.Count) { $cfg | ConvertTo-Json | Set-Content -LiteralPath $CsiApp.Config -Encoding UTF8 }
    else { Remove-Item -LiteralPath $CsiApp.Config -ErrorAction SilentlyContinue }
    Stop-CsiTray
    [void](Start-CsiTray)
    $s = Get-CsiSettings
    Write-Host ("Layout: {0}   Warn: {1}   HideWeeklyBelow: {2}%   Color: {3}   WeeklyColor: {4}   Track: {5}" -f `
        $s.Layout, $s.Warn, $s.HideWeeklyBelow, $s.Color, $s.WeeklyColor, $(if ($s.Track) { $s.Track } else { 'auto (Windows theme)' }))
}

# Saved settings merged over the defaults.
function Get-CsiSettings {
    $s = @{ Layout = 'water'; Warn = 'on'; HideWeeklyBelow = 50; Color = '#3BA8EA'; WeeklyColor = '#A78BFA'; Track = $null }
    $cfg = @{}
    try { $cfg = Get-CsiConfig } catch {}
    foreach ($k in @($cfg.Keys)) { if ($null -ne $cfg[$k] -and "$($cfg[$k])" -ne '') { $s[$k] = $cfg[$k] } }
    if ($s.Layout -notin 'ring', 'water') { $s.Layout = 'water' }   # also maps the old 'pie'
    if ($s.Warn -notin 'on', 'off') { $s.Warn = 'on' }
    $s.HideWeeklyBelow = [int]$s.HideWeeklyBelow
    return $s
}

# ---------------------------------------------------------------- install / uninstall

function Stop-CsiTray {
    # Ask a running instance to quit cleanly (removes its icon), then make sure it is gone.
    $quit = $null
    if ([System.Threading.EventWaitHandle]::TryOpenExisting("Local\$($CsiApp.Name).Quit", [ref]$quit)) {
        [void]$quit.Set(); $quit.Dispose()
    }
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like "*$($CsiApp.Name)\claude-tray.ps1*" })
    foreach ($p in $procs) {
        $proc = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
        if ($proc -and -not $proc.WaitForExit(10000)) { $proc.Kill() }
    }
}

function Start-CsiTray {
    # conhost --headless = no console window flash at all.
    $exe  = Join-Path $env:WINDIR 'System32\conhost.exe'
    $argLine = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$($CsiApp.Script)`""
    Start-Process -FilePath $exe -ArgumentList $argLine -WorkingDirectory $env:USERPROFILE
    return $argLine
}

function Install-CsiTray {
    New-Item -ItemType Directory -Force -Path $CsiApp.Dir | Out-Null
    Stop-CsiTray
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $CsiApp.Script -Force
    } else {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $CsiApp.Source -OutFile $CsiApp.Script -UseBasicParsing
    }
    $argLine = Start-CsiTray
    $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($CsiApp.Shortcut)
    $lnk.TargetPath       = Join-Path $env:WINDIR 'System32\conhost.exe'
    $lnk.Arguments        = $argLine
    $lnk.WorkingDirectory = $env:USERPROFILE
    $lnk.WindowStyle      = 7
    $lnk.Description      = 'Claude usage tray icon'
    $lnk.Save()

    # Windows 11 hides new tray icons in the overflow menu; pin ours to the taskbar once.
    $root = 'HKCU:\Control Panel\NotifyIconSettings'
    for ($i = 0; $i -lt 20 -and (Test-Path $root); $i++) {
        $key = Get-ChildItem $root -ErrorAction SilentlyContinue | Where-Object {
            $v = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            $v.ExecutablePath -like '*\powershell.exe' -and $v.InitialTooltip -like 'Claude usage*'
        } | Select-Object -First 1
        if ($key) {
            if ($null -eq (Get-ItemProperty $key.PSPath).IsPromoted) {
                Set-ItemProperty $key.PSPath -Name IsPromoted -Value 1 -Type DWord
            }
            break
        }
        Start-Sleep -Milliseconds 500
    }
    Write-Host "Claude status icon installed and running. It starts with Windows; right-click it to exit or uninstall."
}

function Uninstall-CsiTray {
    Stop-CsiTray
    Remove-Item -LiteralPath $CsiApp.Shortcut -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $CsiApp.Dir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'Claude status icon uninstalled.'
}

# ---------------------------------------------------------------- tray app

function Get-CsiStatusCode($err) {
    $resp = $err.Exception.Response
    if ($resp) { return [int]$resp.StatusCode }
    return 0
}

# Refresh an expired login the same way Claude Code does, and write the new tokens back so
# Claude Code keeps working too (the refresh token is single-use and gets rotated).
function Update-CsiToken([string]$path) {
    $doc = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $o = $doc.claudeAiOauth
    if (-not $o.refreshToken) { throw 'Login expired - run: claude auth login' }
    $body = @{
        grant_type    = 'refresh_token'
        refresh_token = $o.refreshToken
        client_id     = '9d1c250a-e61b-44d9-88ed-5944d1962f5e'   # Claude Code's public OAuth client
        scope         = (@($o.scopes) -join ' ')
    } | ConvertTo-Json
    try {
        $r = Invoke-RestMethod -Method Post -Uri 'https://platform.claude.com/v1/oauth/token' -ContentType 'application/json' `
            -Body $body -TimeoutSec 30 -UserAgent 'claude-minimalist-status-icon'
    } catch {
        $code = Get-CsiStatusCode $_
        if ($code -ge 400 -and $code -lt 500) { throw 'Login expired - run: claude auth login' }
        throw
    }
    if (-not $r.access_token) { throw 'Token refresh failed' }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $o.accessToken = $r.access_token
    if ($r.refresh_token) { $o.refreshToken = $r.refresh_token }
    $o.expiresAt = $now + [int64]$r.expires_in * 1000
    if ($r.refresh_token_expires_in) {
        $o | Add-Member -NotePropertyName refreshTokenExpiresAt -NotePropertyValue ($now + [int64]$r.refresh_token_expires_in * 1000) -Force
    }
    if ($r.scope) { $o.scopes = @($r.scope -split ' ' | Where-Object { $_ }) }
    # The old refresh token is now spent, so the new one must land in the file no matter what.
    # Temp file + rename (atomic on the same volume); direct write as fallback. UTF-8 without BOM.
    $json = $doc | ConvertTo-Json -Depth 20
    $utf8 = New-Object Text.UTF8Encoding $false
    $tmp = "$path.csi-tmp"
    try {
        [IO.File]::WriteAllText($tmp, $json, $utf8)
        Move-Item -LiteralPath $tmp -Destination $path -Force -ErrorAction Stop
    } catch {
        [IO.File]::WriteAllText($path, $json, $utf8)
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    return $o.accessToken
}

function Get-CsiUsage {
    $path = Join-Path $env:USERPROFILE '.claude\.credentials.json'
    if (-not (Test-Path $path)) { throw 'Sign in to Claude Code first' }
    $oauth = (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).claudeAiOauth
    if (-not $oauth.accessToken) { throw 'Sign in to Claude Code first' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # Refresh only once the token has actually expired: while Claude Code is in use it renews
    # tokens itself before expiry, so this avoids both sides rotating the same refresh token.
    $token = $oauth.accessToken
    $refreshed = $false
    if ($oauth.expiresAt -and [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$oauth.expiresAt) -le [DateTimeOffset]::UtcNow) {
        $token = Update-CsiToken $path; $refreshed = $true
    }
    $call = {
        param($t)
        Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' -TimeoutSec 20 -UserAgent 'claude-minimalist-status-icon' `
            -Headers @{ Authorization = "Bearer $t"; 'anthropic-beta' = 'oauth-2025-04-20' }
    }
    try { $r = & $call $token }
    catch {
        if ((Get-CsiStatusCode $_) -ne 401 -or $refreshed) { throw }
        # Rejected before its expiry time: maybe Claude Code just rotated it. Re-read, else refresh.
        $latest = (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).claudeAiOauth.accessToken
        $token = if ($latest -and $latest -ne $token) { $latest } else { Update-CsiToken $path }
        $r = & $call $token
    }

    $rows = @()
    if ($r.limits) {
        foreach ($l in $r.limits) {
            if ($null -eq $l.percent) { continue }
            $label = switch ($l.kind) {
                'session'       { 'Session' }
                'weekly_all'    { 'Weekly' }
                'weekly_scoped' { "Weekly $($l.scope.model.display_name)".Trim() }
                default         { $l.kind }
            }
            $rows += [pscustomobject]@{ Kind = $l.kind; Label = $label; Pct = [double]$l.percent; Reset = $l.resets_at }
        }
    } else {
        if ($r.five_hour) { $rows += [pscustomobject]@{ Kind = 'session';    Label = 'Session'; Pct = [double]$r.five_hour.utilization; Reset = $r.five_hour.resets_at } }
        if ($r.seven_day) { $rows += [pscustomobject]@{ Kind = 'weekly_all'; Label = 'Weekly';  Pct = [double]$r.seven_day.utilization; Reset = $r.seven_day.resets_at } }
    }
    if (-not $rows) { throw 'No usage data in response' }
    return $rows
}

function Format-CsiReset($iso) {
    if (-not $iso) { return '' }
    $t = if ($iso -is [datetime]) { $iso.ToLocalTime() } else { [DateTimeOffset]::Parse($iso).LocalDateTime }
    if ($t.Date -eq (Get-Date).Date) { return $t.ToString('HH:mm') }
    return $t.ToString('ddd HH:mm')
}

function Start-CsiTrayApp {
    $created = $false
    $mutex = New-Object System.Threading.Mutex($true, "Local\$($CsiApp.Name)", [ref]$created)
    if (-not $created) { return }   # already running
    $quit = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, "Local\$($CsiApp.Name).Quit")

    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    if (-not ('Csi.Native' -as [type])) {
        Add-Type -Namespace Csi -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr h);
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
'@
    }
    [void][Csi.Native]::SetProcessDPIAware()   # crisp icon on scaled displays
    # Never show the WinForms crash dialog: log the error and keep running.
    [Windows.Forms.Application]::SetUnhandledExceptionMode([Windows.Forms.UnhandledExceptionMode]::CatchException)
    [Windows.Forms.Application]::add_ThreadException({
        param($sender, $e)
        try { Add-Content -LiteralPath (Join-Path $CsiApp.Dir 'error.log') -Value "$(Get-Date -Format s)  $($e.Exception.Message)" } catch {}
    })

    $Colors = @{
        Ok   = [Drawing.Color]::FromArgb(59, 168, 234)
        Warn = [Drawing.Color]::FromArgb(245, 180, 0)
        Crit = [Drawing.Color]::FromArgb(229, 72, 77)
        Off  = [Drawing.Color]::FromArgb(140, 140, 140)
    }
    $State = @{ Next = [DateTime]::MinValue; Handle = [IntPtr]::Zero; Rows = @() }

    # Settings (see the header). Bad colour values fall back to the defaults.
    $Opt = Get-CsiSettings
    $toColor = { param($v, $fallback) try { ConvertTo-CsiColor $v } catch { ConvertTo-CsiColor $fallback } }
    $Colors.Session = & $toColor $Opt.Color '#3BA8EA'
    $Colors.Weekly  = & $toColor $Opt.WeeklyColor '#A78BFA'
    $customTrack = $null; if ($Opt.Track) { try { $customTrack = ConvertTo-CsiColor $Opt.Track } catch {} }

    # Default track follows the taskbar theme so it is visible on both dark and light.
    $trackColor = {
        if ($customTrack) { return $customTrack }
        $light = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue).SystemUsesLightTheme -eq 1
        if ($light) { [Drawing.Color]::FromArgb(90, 0, 0, 0) } else { [Drawing.Color]::FromArgb(150, 255, 255, 255) }
    }

    # Each limit gets its own colour: its base colour, or amber/red once that limit runs high.
    $levelColor = {
        param($p, $base)
        if ($Opt.Warn -eq 'on' -and $p -ge 90) { $Colors.Crit }
        elseif ($Opt.Warn -eq 'on' -and $p -ge 70) { $Colors.Warn }
        else { $base }
    }

    # Ring = session. Optional water level inside = weekly ($fillColor $null -> ring only).
    # With the water level shown the ring gets thinner so the level has room to be readable.
    $setIcon = {
        param([double]$pct, $ring, [double]$levelPct = 0, $fillColor = $null)
        $s = [Windows.Forms.SystemInformation]::SmallIconSize.Width
        $bmp = New-Object Drawing.Bitmap $s, $s
        $g = [Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $water = $null -ne $fillColor
        if ($water) { $w = [Math]::Max(2.0, $s * 0.1375); $pad = $w / 2 + 0.3 }
        else        { $w = [Math]::Max(2.0, $s * 0.17);   $pad = $w / 2 + 0.5 }
        $rect = New-Object Drawing.RectangleF $pad, $pad, ($s - 2 * $pad), ($s - 2 * $pad)
        $trackC = & $trackColor
        $track = New-Object Drawing.Pen $trackC, $w
        $g.DrawEllipse($track, $rect)
        if ($pct -gt 0) {
            $pen = New-Object Drawing.Pen $ring, $w
            $g.DrawArc($pen, $rect, -90, [float]([Math]::Max(4, 3.6 * [Math]::Min(100, $pct))))
            $pen.Dispose()
        }
        if ($water) {
            $rp = $s / 2 - $pad - $w / 2 - [Math]::Max(0.8, $s * 0.05)
            $x0 = [float]($s / 2 - $rp); $d = [float](2 * $rp)
            $tb = New-Object Drawing.SolidBrush $trackC
            $g.FillEllipse($tb, $x0, $x0, $d, $d); $tb.Dispose()
            if ($levelPct -gt 0) {
                $clip = New-Object Drawing.Drawing2D.GraphicsPath
                $clip.AddEllipse($x0, $x0, $d, $d)
                $g.SetClip($clip)
                $lh = [float]($d * [Math]::Min(100, $levelPct) / 100)
                $lb = New-Object Drawing.SolidBrush $fillColor
                $g.FillRectangle($lb, [float]0, [float]($x0 + $d - $lh), [float]$s, $lh)
                $lb.Dispose(); $g.ResetClip(); $clip.Dispose()
            }
        }
        $track.Dispose(); $g.Dispose()
        $h = $bmp.GetHicon(); $bmp.Dispose()
        $ni.Icon = [Drawing.Icon]::FromHandle($h)
        if ($State.Handle -ne [IntPtr]::Zero) { [void][Csi.Native]::DestroyIcon($State.Handle) }
        $State.Handle = $h
    }

    # Tooltip updates live; the info lines of the menu are rebuilt only when it opens.
    $setText = {
        param([string]$tip, [string[]]$lines)
        $ni.Text = if ($tip.Length -gt 63) { $tip.Substring(0, 63) } else { $tip }
        $State.Lines = $lines
    }

    $buildMenu = {
        $menu.Items.Clear()
        foreach ($l in $State.Lines) { $it = $menu.Items.Add($l); $it.Enabled = $false }
        [void]$menu.Items.Add('-')
        [void]$menu.Items.Add('Refresh', $null, { $State.Next = [DateTime]::MinValue })
        [void]$menu.Items.Add('Open usage page', $null, { Start-Process 'https://claude.ai/settings/usage' })
        [void]$menu.Items.Add('-')
        [void]$menu.Items.Add('Uninstall', $null, {
            $a = [Windows.Forms.MessageBox]::Show('Remove the Claude status icon from this PC?', 'Claude status icon', 'YesNo', 'Question')
            if ($a -eq 'Yes') {
                Remove-Item -LiteralPath $CsiApp.Shortcut -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $CsiApp.Dir -Recurse -Force -ErrorAction SilentlyContinue
                & $exitApp
            }
        })
        [void]$menu.Items.Add('Exit', $null, { & $exitApp })
    }

    $update = {
        try {
            $rows = Get-CsiUsage
            $session = $rows | Where-Object Kind -eq 'session' | Select-Object -First 1
            $weekly  = $rows | Where-Object Kind -like 'weekly*' | Sort-Object Pct -Descending | Select-Object -First 1
            $sp = if ($session) { $session.Pct } else { 0 }
            $wp = if ($weekly) { $weekly.Pct } else { 0 }
            $weeklyColor = $null
            if ($Opt.Layout -eq 'water' -and $weekly -and $wp -ge $Opt.HideWeeklyBelow) { $weeklyColor = & $levelColor $wp $Colors.Weekly }
            & $setIcon $sp (& $levelColor $sp $Colors.Session) $wp $weeklyColor
            $tip = @()
            if ($session) { $tip += "Session $([int]$sp)% - $(Format-CsiReset $session.Reset)" }
            if ($weekly)  { $tip += "$($weekly.Label) $([int]$wp)% - $(Format-CsiReset $weekly.Reset)" }
            $lines = $rows | ForEach-Object { "$($_.Label)  $([int]$_.Pct)%    resets $(Format-CsiReset $_.Reset)" }
            & $setText ($tip -join "`n") $lines
            $State.LastGood = Get-Date; $State.LastTip = $tip -join "`n"; $State.LastLines = $lines
            $State.Next = (Get-Date).AddMinutes(3)
        } catch {
            $msg = $_.Exception.Message
            $resp = $_.Exception.Response
            $State.Next = (Get-Date).AddMinutes(1)
            if ($resp -and [int]$resp.StatusCode -eq 429) {
                $msg = 'Rate limited, retrying later'
                $ra = 0; [void][int]::TryParse($resp.Headers['Retry-After'], [ref]$ra)
                $State.Next = (Get-Date).AddSeconds([Math]::Max(120, $ra))
            } elseif ($resp -and [int]$resp.StatusCode -eq 401) {
                $msg = 'Login expired - run: claude auth login'
            }
            if ($msg -notlike 'Login expired*' -and $State.LastGood -and ((Get-Date) - $State.LastGood).TotalHours -lt 6) {
                # Transient problem: keep the last ring, mark the numbers as stale.
                $since = $State.LastGood.ToString('HH:mm')
                & $setText "Stale since ${since}`n$($State.LastTip)" (@("Stale since ${since}: $msg") + $State.LastLines)
            } else {
                & $setIcon 0 $Colors.Off
                & $setText "Claude usage: $msg" @("Error: $msg")
            }
        }
    }

    # One cheap 5 s tick: quit signal, plus poll when due. After sleep/resume the
    # wall-clock check notices the gap and refreshes immediately.
    $tick = {
        if ($quit.WaitOne(0)) { & $exitApp; return }
        if ((Get-Date) -ge $State.Next) { & $update }
    }

    $exitApp = {
        $timer.Stop()
        $ni.Visible = $false
        [Windows.Forms.Application]::Exit()
    }

    $menu  = New-Object Windows.Forms.ContextMenuStrip
    $ni    = New-Object Windows.Forms.NotifyIcon
    $ni.ContextMenuStrip = $menu
    $menu.add_Opening({ param($sender, $e) & $buildMenu; $e.Cancel = $false })
    $ni.add_MouseClick({ param($sender, $e) if ($e.Button -eq 'Left') { $State.Next = [DateTime]::MinValue; & $tick } })
    & $setIcon 0 $Colors.Off
    & $setText 'Claude usage: loading...' @('Loading...')
    & $buildMenu
    $ni.Visible = $true

    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 5000
    $timer.add_Tick({ & $tick })
    $timer.Start()
    & $tick

    try { [Windows.Forms.Application]::Run() }
    finally {
        $ni.Visible = $false; $ni.Dispose()
        if ($State.Handle -ne [IntPtr]::Zero) { [void][Csi.Native]::DestroyIcon($State.Handle) }
        $quit.Dispose(); $mutex.ReleaseMutex(); $mutex.Dispose()
    }
}

# ---------------------------------------------------------------- entry point

if ($Uninstall) { Uninstall-CsiTray }
elseif ($Reset -or $Layout -or $Warn -or $HideWeeklyBelow -ge 0 -or $Color -or $WeeklyColor -or $Track) { Set-CsiConfig }
elseif ($Run -or ($PSCommandPath -and $PSCommandPath -eq $CsiApp.Script)) { Start-CsiTrayApp }
else { Install-CsiTray }
