$MusicDir = "G:\music"

if (-not (Test-Path $MusicDir)) {
    Write-Error "Directory not found: $MusicDir"
    exit
}

# Load WinMM
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinMM {
    [DllImport("winmm.dll")]
    public static extern int mciSendString(string command, StringBuilder buffer, int bufferSize, IntPtr hwndCallback);
}
"@

# Notification support
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Show-Notification($title, $text) {
    $notify = New-Object System.Windows.Forms.NotifyIcon
    $notify.Icon = [System.Drawing.SystemIcons]::Information
    $notify.BalloonTipTitle = $title
    $notify.BalloonTipText = $text
    $notify.Visible = $true
    $notify.ShowBalloonTip(3000)
    Start-Sleep -Milliseconds 3500
    $notify.Dispose()
}

# Load songs
$global:Songs = Get-ChildItem $MusicDir -Recurse -Include *.mp3, *.wav | Select-Object -ExpandProperty FullName

if (-not $global:Songs) {
    Write-Error "No audio files found"
    exit
}

function Shuffle-Queue {
    $global:Queue = $global:Songs | Sort-Object { Get-Random }
    $global:Index = 0
}

function Show-Queue {
    Write-Host "`n--- QUEUE ---"
    for ($i = 0; $i -lt $global:Queue.Count; $i++) {
        if ($i -eq $global:Index) {
            Write-Host ">> $([System.IO.Path]::GetFileName($global:Queue[$i]))" -ForegroundColor Green
        } else {
            Write-Host "   $([System.IO.Path]::GetFileName($global:Queue[$i]))"
        }
    }
    $loopStatus   = if ($global:LoopMode)  { "ON" } else { "OFF" }
    $repeatStatus = if ($global:RepeatOne) { "ON" } else { "OFF" }
    $searchStatus = if ($global:SearchMode) { " [SEARCH MODE]" } else { "" }
    Write-Host "   [Loop: $loopStatus]  [Repeat: $repeatStatus]  [Vol: $global:Volume%]$searchStatus" -ForegroundColor DarkCyan
    Write-Host "--------------`n"
}

function Get-TrackDuration {
    $buf = New-Object System.Text.StringBuilder 128
    [WinMM]::mciSendString("status $global:Alias length", $buf, 128, [IntPtr]::Zero) | Out-Null
    return [int]$buf.ToString()
}

function Get-TrackPosition {
    $buf = New-Object System.Text.StringBuilder 128
    [WinMM]::mciSendString("status $global:Alias position", $buf, 128, [IntPtr]::Zero) | Out-Null
    return [int]$buf.ToString()
}

function Format-Time($ms) {
    $totalSec = [math]::Floor($ms / 1000)
    $min = [math]::Floor($totalSec / 60)
    $sec = $totalSec % 60
    return "{0}:{1:00}" -f $min, $sec
}

function Show-Progress {
    if (-not $global:Alias) { return }
    $pos = Get-TrackPosition
    $dur = Get-TrackDuration
    if ($dur -le 0) { return }
    $posStr = Format-Time $pos
    $durStr = Format-Time $dur
    $pct = [math]::Floor(($pos / $dur) * 30)
    $bar = ("[" + "#" * $pct + "-" * (30 - $pct) + "]")
    $state = if ($global:Paused) { "PAUSED" } else { "PLAYING" }
    Write-Host "`r  $state  $bar  $posStr / $durStr   " -NoNewline
}

function Set-Volume($vol) {
    $global:Volume = [math]::Max(0, [math]::Min(100, $vol))
    $scaled = [math]::Floor($global:Volume * 10)
    [WinMM]::mciSendString("setaudio $global:Alias volume to $scaled", $null, 0, [IntPtr]::Zero) | Out-Null
    Write-Host "`r  Volume: $global:Volume%   " -NoNewline
}

function Play-Current {
    $file = $global:Queue[$global:Index]
    $global:Alias = "audio$([guid]::NewGuid().ToString('N'))"
    Write-Host "`nNow playing: $(Split-Path $file -Leaf)" -ForegroundColor Cyan
    Show-Notification "Now Playing" (Split-Path $file -Leaf)
    [WinMM]::mciSendString("open `"$file`" type mpegvideo alias $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
    [WinMM]::mciSendString("play $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
    $scaled = [math]::Floor($global:Volume * 10)
    [WinMM]::mciSendString("setaudio $global:Alias volume to $scaled", $null, 0, [IntPtr]::Zero) | Out-Null
    $global:Paused = $false
}

function Stop-Current {
    if ($global:Alias) {
        [WinMM]::mciSendString("stop $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
        [WinMM]::mciSendString("close $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
    }
}

function Toggle-Pause {
    if ($global:Paused) {
        [WinMM]::mciSendString("resume $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
        $global:Paused = $false
    } else {
        [WinMM]::mciSendString("pause $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
        $global:Paused = $true
    }
}

function Toggle-Loop {
    $global:LoopMode = -not $global:LoopMode
    $status = if ($global:LoopMode) { "ON" } else { "OFF" }
    Write-Host "`n  Loop mode: $status" -ForegroundColor DarkCyan
}

function Toggle-Repeat {
    $global:RepeatOne = -not $global:RepeatOne
    $status = if ($global:RepeatOne) { "ON" } else { "OFF" }
    Write-Host "`n  Repeat current song: $status" -ForegroundColor DarkCyan
}

function Next-Track {
    Stop-Current
    $global:Index++
    if ($global:Index -ge $global:Queue.Count) { $global:Index = 0 }
    Play-Current
}

function Prev-Track {
    Stop-Current
    $global:Index--
    if ($global:Index -lt 0) { $global:Index = $global:Queue.Count - 1 }
    Play-Current
}

function Search-And-Play {
    # Stop progress line and pause playback while user is typing
    Write-Host ""
    $wasPlaying = -not $global:Paused
    if ($wasPlaying) {
        [WinMM]::mciSendString("pause $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
        $global:Paused = $true
    }

    Write-Host "Search: " -NoNewline -ForegroundColor Yellow
    $query = Read-Host

    # Resume if user cancels with blank input
    if (-not $query) {
        if ($wasPlaying) {
            [WinMM]::mciSendString("resume $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
            $global:Paused = $false
        }
        Write-Host "  Search cancelled." -ForegroundColor DarkGray
        return
    }

    $results = $global:Songs | Where-Object {
        [System.IO.Path]::GetFileName($_) -like "*$query*"
    }

    if (-not $results) {
        if ($wasPlaying) {
            [WinMM]::mciSendString("resume $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
            $global:Paused = $false
        }
        Write-Host "  No matches found for '$query'." -ForegroundColor Red
        return
    }

    $list = @($results)
    Write-Host ""
    for ($i = 0; $i -lt $list.Count; $i++) {
        Write-Host "  $($i + 1). $([System.IO.Path]::GetFileName($list[$i]))"
    }
    Write-Host ""
    Write-Host "Enter number (or 0 to cancel): " -NoNewline -ForegroundColor Yellow
    $choice = Read-Host

    if ($choice -eq "0" -or $choice -eq "") {
        if ($wasPlaying) {
            [WinMM]::mciSendString("resume $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
            $global:Paused = $false
        }
        Write-Host "  Cancelled." -ForegroundColor DarkGray
        return
    }

    $choiceInt = 0
    if (-not [int]::TryParse($choice, [ref]$choiceInt) -or $choiceInt -lt 1 -or $choiceInt -gt $list.Count) {
        if ($wasPlaying) {
            [WinMM]::mciSendString("resume $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
            $global:Paused = $false
        }
        Write-Host "  Invalid selection." -ForegroundColor Red
        return
    }

    # User picked a song — enter search mode
    $chosen = $list[$choiceInt - 1]
    Stop-Current

    # Save current queue and state, build single-song queue
    $global:PreSearchQueue    = $global:Queue
    $global:PreSearchIndex    = $global:Index
    $global:PreSearchLoop     = $global:LoopMode
    $global:PreSearchRepeat   = $global:RepeatOne
    $global:SearchMode        = $true

    $global:Queue      = @($chosen)
    $global:Index      = 0
    $global:LoopMode   = $false
    $global:RepeatOne  = $false

    Write-Host "  [Search mode: playing single song]" -ForegroundColor DarkYellow
    Play-Current
}

function Exit-SearchMode {
    # Restore full queue and previous states
    $global:Queue      = $global:PreSearchQueue
    $global:Index      = $global:PreSearchIndex
    $global:LoopMode   = $false
    $global:RepeatOne  = $false
    $global:SearchMode = $false
    #Write-Host "`n  Search mode ended. Queue restored." -ForegroundColor DarkGray
}

function Start-EndOfQueueCountdown {
    $global:WaitingForLoop = $true

    if ($global:SearchMode) {
        $songName = [System.IO.Path]::GetFileName($global:Queue[0])
        Write-Host "`nFinished: $songName" -ForegroundColor DarkYellow
        Write-Host "Press L to replay this song, or exiting in..." -ForegroundColor Yellow
        Show-Notification "Song Finished" "Press L to replay, or player exits in 5 seconds."
    } else {
        Write-Host "`nQueue finished. Press L to loop, or exiting in..." -ForegroundColor Yellow
        Show-Notification "Queue Finished" "Press L to loop, or player exits in 5 seconds."
    }

    for ($i = 5; $i -ge 1; $i--) {
        Write-Host "$i..." -ForegroundColor Yellow -NoNewline
        for ($t = 0; $t -lt 4; $t++) {
            if ([console]::KeyAvailable) {
                $k = [console]::ReadKey($true).Key
                if ($k -eq "L") {
                    Write-Host ""
                    if ($global:SearchMode) {
                        # Replay the single searched song
                        Write-Host "  Replaying searched song..." -ForegroundColor Green
                        $global:Index = 0
                        $global:WaitingForLoop = $false
                        Play-Current
                    } else {
                        Write-Host "  Looping queue from start!" -ForegroundColor Green
                        $global:Index = 0
                        $global:WaitingForLoop = $false
                        Play-Current
                    }
                    return
                }
                if ($k -eq "X") {
                    Write-Host ""
                    Stop-Current
                    $global:Running = $false
                    $global:WaitingForLoop = $false
                    if ($global:SearchMode) { Exit-SearchMode }
                    return
                }
            }
            Start-Sleep -Milliseconds 250
        }
    }

    Write-Host ""
    Write-Host "Exiting." -ForegroundColor Red
    Stop-Current
    if ($global:SearchMode) { Exit-SearchMode }
    $global:Running = $false
    $global:WaitingForLoop = $false
}

# Initialize
$global:LoopMode       = $false
$global:RepeatOne      = $false
$global:Paused         = $false
$global:Running        = $true
$global:WaitingForLoop = $false
$global:Volume         = 100
$global:SearchMode     = $false
$global:PreSearchQueue = $null
$global:PreSearchIndex = 0

Shuffle-Queue
Show-Queue
Play-Current

Write-Host "Controls:"
Write-Host "  N = Next       | B = Previous  | P = Play/Pause"
Write-Host "  S = Shuffle    | Q = Show Queue | F = Search"
Write-Host "  L = Toggle Loop (queue) | R = Toggle Repeat (current song)"
Write-Host "  + = Volume Up  | - = Volume Down"
Write-Host "  X = Exit"
Write-Host "  (Loop and Repeat are OFF by default.)"
Write-Host ""

# Main loop
while ($global:Running) {

    if (-not $global:WaitingForLoop) { Show-Progress }

    if (-not $global:WaitingForLoop -and [console]::KeyAvailable) {
        $key = [console]::ReadKey($true).Key
        switch ($key) {
            "N"        { Write-Host ""; Next-Track }
            "B"        { Write-Host ""; Prev-Track }
            "P"        { Toggle-Pause }
            "S"        {
                # Exit search mode if active before shuffling
                if ($global:SearchMode) { Exit-SearchMode }
                Write-Host "`n  Shuffling..." -ForegroundColor Yellow
                Stop-Current
                Shuffle-Queue
                Show-Queue
                Play-Current
            }
            "Q"        { Write-Host ""; Show-Queue }
            "L"        { Toggle-Loop }
            "R"        { Toggle-Repeat }
            "F"        { Search-And-Play }
            "OemPlus"  { Set-Volume ($global:Volume + 10) }
            "OemMinus" { Set-Volume ($global:Volume - 10) }
            "X"        {
                Write-Host ""
                Stop-Current
                $global:Running = $false
            }
        }
    }

    # Auto-next when song ends
    if (-not $global:WaitingForLoop -and $global:Alias) {
        $status = New-Object System.Text.StringBuilder 128
        [WinMM]::mciSendString("status $global:Alias mode", $status, 128, [IntPtr]::Zero) | Out-Null

        if ($status.ToString() -eq "stopped" -and -not $global:Paused) {
            if ($global:RepeatOne) {
                Stop-Current
                Play-Current
            } elseif ($global:SearchMode) {
                # Single song queue always goes to countdown
                Start-EndOfQueueCountdown
            } elseif ($global:Index + 1 -ge $global:Queue.Count) {
                if ($global:LoopMode) {
                    Write-Host "`n  Restarting queue..." -ForegroundColor DarkCyan
                    $global:Index = 0
                    Play-Current
                } else {
                    Start-EndOfQueueCountdown
                }
            } else {
                $global:Index++
                Play-Current
            }
        }
    }

    Start-Sleep -Milliseconds 200
}