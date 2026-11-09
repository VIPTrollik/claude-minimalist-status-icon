# Claude minimalist status icon - a tray ring showing your Claude plan usage.
# https://github.com/VIPTrollik/claude-minimalist-status-icon
#
#   Install / update :  irm https://raw.githubusercontent.com/VIPTrollik/claude-minimalist-status-icon/main/claude-tray.ps1 | iex
#   Uninstall        :  tray icon > right-click > Uninstall
#
# Run from anywhere except the install folder -> installs itself (copy, startup shortcut, launch).
# Run from the install folder (what the startup shortcut does) -> shows the tray icon.
param([switch]$Uninstall, [switch]$Run)

$CsiApp = @{
    Name     = 'ClaudeStatusIcon'
    Source   = 'https://raw.githubusercontent.com/VIPTrollik/claude-minimalist-status-icon/main/claude-tray.ps1'
    Dir      = Join-Path $env:LOCALAPPDATA 'ClaudeStatusIcon'
    Script   = Join-Path $env:LOCALAPPDATA 'ClaudeStatusIcon\claude-tray.ps1'
    Shortcut = Join-Path ([Environment]::GetFolderPath('Startup')) 'ClaudeStatusIcon.lnk'
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

function Get-CsiUsage {
    $path = Join-Path $env:USERPROFILE '.claude\.credentials.json'
    if (-not (Test-Path $path)) { throw 'Sign in to Claude Code first' }
    $oauth = (Get-Content $path -Raw | ConvertFrom-Json).claudeAiOauth
    if (-not $oauth.accessToken) { throw 'Sign in to Claude Code first' }
    if ($oauth.expiresAt -and [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$oauth.expiresAt) -lt [DateTimeOffset]::UtcNow) {
        throw 'Token expired - open Claude Code'
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $r = Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' -TimeoutSec 20 -UserAgent 'claude-minimalist-status-icon' `
        -Headers @{ Authorization = "Bearer $($oauth.accessToken)"; 'anthropic-beta' = 'oauth-2025-04-20' }

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

    $levelColor = { param($p) if ($p -ge 90) { $Colors.Crit } elseif ($p -ge 70) { $Colors.Warn } else { $Colors.Ok } }

    $setIcon = {
        param([double]$pct, $ring, $dot)
        $s = [Windows.Forms.SystemInformation]::SmallIconSize.Width
        $bmp = New-Object Drawing.Bitmap $s, $s
        $g = [Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $w = [Math]::Max(2.0, $s * 0.17)
        $pad = $w / 2 + 0.5
        $rect = New-Object Drawing.RectangleF $pad, $pad, ($s - 2 * $pad), ($s - 2 * $pad)
        $track = New-Object Drawing.Pen ([Drawing.Color]::FromArgb(80, $ring)), $w
        $g.DrawEllipse($track, $rect)
        if ($pct -gt 0) {
            $pen = New-Object Drawing.Pen $ring, $w
            $g.DrawArc($pen, $rect, -90, [float]([Math]::Max(4, 3.6 * [Math]::Min(100, $pct))))
            $pen.Dispose()
        }
        $d = $s * 0.28
        $brush = New-Object Drawing.SolidBrush $dot
        $g.FillEllipse($brush, ($s - $d) / 2, ($s - $d) / 2, $d, $d)
        $brush.Dispose(); $track.Dispose(); $g.Dispose()
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
            & $setIcon $sp (& $levelColor $sp) (& $levelColor $wp)
            $tip = @()
            if ($session) { $tip += "Session $([int]$sp)% - $(Format-CsiReset $session.Reset)" }
            if ($weekly)  { $tip += "$($weekly.Label) $([int]$wp)% - $(Format-CsiReset $weekly.Reset)" }
            $lines = $rows | ForEach-Object { "$($_.Label)  $([int]$_.Pct)%    resets $(Format-CsiReset $_.Reset)" }
            & $setText ($tip -join "`n") $lines
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
                $msg = 'Token expired - open Claude Code'
            }
            & $setIcon 0 $Colors.Off $Colors.Off
            & $setText "Claude usage: $msg" @("Error: $msg")
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
    & $setIcon 0 $Colors.Off $Colors.Off
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
elseif ($Run -or ($PSCommandPath -and $PSCommandPath -eq $CsiApp.Script)) { Start-CsiTrayApp }
else { Install-CsiTray }
