$MusicDir = $PSScriptRoot

$SongArg = if ($args.Count -gt 0) { $args[0] } else { "" }

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


$global:CliSongTarget = $null

if ($SongArg -ne "") {
    $results = $global:Songs | Where-Object {
        [System.IO.Path]::GetFileName($_) -like "*$SongArg*"
    }

    if (-not $results) {
        Write-Host "No songs found matching '$SongArg'." -ForegroundColor Red
        exit
    }

    $list = @($results)

    if ($list.Count -eq 1) {
        $global:CliSongTarget = $list[0]
    } else {
        Write-Host ""
        Write-Host "  Looking for '$SongArg' - did you mean one of these?" -ForegroundColor Yellow
        Write-Host ""
        for ($i = 0; $i -lt $list.Count; $i++) {
            Write-Host "  $($i + 1). $([System.IO.Path]::GetFileName($list[$i]))"
        }
        Write-Host ""
        Write-Host "Enter number (or 0 to cancel): " -NoNewline -ForegroundColor Yellow
        $choice = Read-Host

        if ($choice -eq "0" -or $choice -eq "") {
            Write-Host "  Cancelled." -ForegroundColor DarkGray
            exit
        }

        $choiceInt = 0
        if (-not [int]::TryParse($choice, [ref]$choiceInt) -or $choiceInt -lt 1 -or $choiceInt -gt $list.Count) {
            Write-Host "  Invalid selection." -ForegroundColor Red
            exit
        }

        $global:CliSongTarget = $list[$choiceInt - 1]
    }
}

function Shuffle-Queue {
    $currentFile = if ($global:PreSearchFile) {
        $global:PreSearchFile                              
    } elseif ($global:Queue -and $global:Queue.Count -gt 0) {
        $global:Queue[$global:Index]
    } else { $null }

    $global:PreSearchFile = $null                        

    $global:Queue       = $global:Songs | Sort-Object { Get-Random }
    $global:Index       = 0
    $global:CursorIndex = 0

    if ($currentFile) {
        $foundAt = [array]::IndexOf($global:Queue, $currentFile)
        $global:LastPlayedIndex = if ($foundAt -ge 0) { $foundAt } else { 0 }
    } else {
        $global:LastPlayedIndex = 0
    }
}

function Show-Queue {
    Write-Host "`n--- QUEUE ---"
    for ($i = 0; $i -lt $global:Queue.Count; $i++) {
        $name = [System.IO.Path]::GetFileName($global:Queue[$i])
        if ($i -eq $global:Index -and $i -eq $global:LastPlayedIndex) {
            Write-Host ">> * $name" -ForegroundColor Cyan
        } elseif ($i -eq $global:Index) {
            Write-Host ">>   $name" -ForegroundColor Green
        } elseif ($i -eq $global:LastPlayedIndex) {
            Write-Host "  *  $name" -ForegroundColor Yellow
        } else {
            Write-Host "     $name"
        }
    }
    $loopStatus   = if ($global:LoopMode)   { "ON" } else { "OFF" }
    $repeatStatus = if ($global:RepeatOne)  { "ON" } else { "OFF" }
    $searchStatus = if ($global:SearchMode) { " [SEARCH MODE]" } else { "" }
    Write-Host "   [Loop: $loopStatus]  [Repeat: $repeatStatus]  [Vol: $global:Volume%]$searchStatus" -ForegroundColor DarkCyan
    Write-Host "--------------"
    Write-Host "  Q = View Queue/Navigate" -ForegroundColor DarkGray
}

function Open-Navigator {
    $global:CursorIndex = $global:Index

    while ($true) {
        [console]::Clear()
        Write-Host "`n--- NAVIGATOR ---"
        for ($i = 0; $i -lt $global:Queue.Count; $i++) {
            $name = [System.IO.Path]::GetFileName($global:Queue[$i])
            if ($i -eq $global:Index -and $i -eq $global:CursorIndex) {
                Write-Host ">> * $name" -ForegroundColor Cyan
            } elseif ($i -eq $global:Index) {
                Write-Host ">>   $name" -ForegroundColor Green
            } elseif ($i -eq $global:CursorIndex) {
                Write-Host "  *  $name" -ForegroundColor Yellow
            } else {
                Write-Host "     $name"
            }
        }
        $loopStatus   = if ($global:LoopMode)   { "ON" } else { "OFF" }
        $repeatStatus = if ($global:RepeatOne)  { "ON" } else { "OFF" }
        $searchStatus = if ($global:SearchMode) { " [SEARCH MODE]" } else { "" }
        Write-Host "   [Loop: $loopStatus]  [Repeat: $repeatStatus]  [Vol: $global:Volume%]$searchStatus" -ForegroundColor DarkCyan
        Write-Host "--------------"
        Write-Host "  Up/Down = Navigate | Enter = Play | F = Search | P = Pause | Q = Close" -ForegroundColor DarkGray
        Write-Host ""

        $k = [console]::ReadKey($true).Key
        switch ($k) {
            "UpArrow" {
                if ($global:CursorIndex -gt 0) {
                    $global:CursorIndex--
                } else {
                    $global:CursorIndex = $global:Queue.Count - 1
                }
            }
            "DownArrow" {
                if ($global:CursorIndex -lt ($global:Queue.Count - 1)) {
                    $global:CursorIndex++
                } else {
                    $global:CursorIndex = 0
                }
            }
            "Enter" {
                $global:LastPlayedIndex = $global:Index
                Stop-Current
                $global:Index = $global:CursorIndex
                [console]::Clear()
                Play-Current
                return
            }
            "P" { Toggle-Pause }
            "F" {
                [console]::Clear()
                Write-Host "Search: " -NoNewline -ForegroundColor Yellow
                $query = Read-Host

                if (-not $query) { break }

                $results = $global:Songs | Where-Object {
                    [System.IO.Path]::GetFileName($_) -like "*$query*"
                }

                if (-not $results) {
                    Write-Host "  No match found for '$query'." -ForegroundColor Red
                    Start-Sleep -Milliseconds 800
                    break
                }

                $list = @($results)
                Write-Host ""
                for ($i = 0; $i -lt $list.Count; $i++) {
                    Write-Host "  $($i + 1). $([System.IO.Path]::GetFileName($list[$i]))"
                }
                Write-Host ""
                Write-Host "Enter number (append 'a' to add to queue only, 0 to cancel): " -NoNewline -ForegroundColor Yellow
                $choice = Read-Host

                if ($choice -eq "0" -or $choice -eq "") { break }

                $addOnly = $false
                if ($choice.Length -ge 2 -and $choice[-1] -eq 'A') {
                    $addOnly = $true
                    $choice = $choice.Substring(0, $choice.Length - 1)
                }

                $choiceInt = 0
                if (-not [int]::TryParse($choice, [ref]$choiceInt) -or $choiceInt -lt 1 -or $choiceInt -gt $list.Count) {
                    Write-Host "  Invalid selection." -ForegroundColor Red
                    Start-Sleep -Milliseconds 800
                    break
                }

                $chosen = $list[$choiceInt - 1]

                if ($addOnly) {
                    if ($global:Queue -contains $chosen) {
                        Write-Host "  Song already in queue." -ForegroundColor Yellow
                        Start-Sleep -Milliseconds 800
                        break
                    }
                    $global:Queue = $global:Queue + $chosen
                    Write-Host "  Added to queue." -ForegroundColor Green
                    Start-Sleep -Milliseconds 800
                    break
                }

                $newIndex = [array]::IndexOf($global:Queue, $chosen)
                if ($newIndex -lt 0) {
                    $global:Queue = $global:Queue + $chosen
                    $newIndex     = $global:Queue.Count - 1
                }

                $global:LastPlayedIndex = $global:Index
                Stop-Current
                $global:Index       = $newIndex
                $global:CursorIndex = $newIndex
                [console]::Clear()
                Play-Current
                return
            }
            "Q" {
                [console]::Clear()
                Write-Host "Now playing: $(Split-Path $global:Queue[$global:Index] -Leaf)" -ForegroundColor Cyan
                Write-Host ""
                Write-Host "Controls:"
                Write-Host "  N = Next       | B = Previous  | P = Pause/Play"
                Write-Host "  S = Shuffle    | Q = View Queue | QQ = Navigate | F = Search"
                Write-Host "  L = Toggle Loop (queue) | R = Toggle Repeat (current song)"
                Write-Host "  + = Volume Up  | - = Volume Down"
                Write-Host "  X = Exit"
                Write-Host ""
                return
            }
        }
    }
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
    $global:LastPlayedIndex = $global:Index
    Stop-Current
    $global:Index++
    if ($global:Index -ge $global:Queue.Count) { $global:Index = 0 }
    Play-Current
}

function Prev-Track {
    $global:LastPlayedIndex = $global:Index
    Stop-Current
    $global:Index--
    if ($global:Index -lt 0) { $global:Index = $global:Queue.Count - 1 }
    Play-Current
}

function Search-And-Play {
    Write-Host ""
    $wasPlaying = -not $global:Paused
    if ($wasPlaying) {
        [WinMM]::mciSendString("pause $global:Alias", $null, 0, [IntPtr]::Zero) | Out-Null
        $global:Paused = $true
    }

    Write-Host "Search: " -NoNewline -ForegroundColor Yellow
    $query = Read-Host

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

    $chosen = $list[$choiceInt - 1]
    $global:LastPlayedIndex = $global:Index
    Stop-Current

    $global:PreSearchQueue  = $global:Queue
    $global:PreSearchIndex  = $global:Index
	$global:PreSearchFile   = $chosen
    $global:SearchMode      = $true

    $global:Queue     = @($chosen)
    $global:Index     = 0
    $global:LoopMode  = $false
    $global:RepeatOne = $false

    Write-Host "  [Search mode: playing single song]" -ForegroundColor DarkYellow
    Play-Current
}

function Exit-SearchMode {
    $global:PreSearchFile   = $global:Queue[$global:Index]
    $global:Queue           = $global:PreSearchQueue
    $global:Index           = $global:PreSearchIndex
    $global:LoopMode        = $false
    $global:RepeatOne       = $false
    $global:SearchMode      = $false
}

function Start-EndOfQueueCountdown {
    $global:WaitingForLoop = $true

    if ($global:Queue.Count -eq 1) {
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
                    $global:LastPlayedIndex = $global:Index
                    $global:Index           = 0
                    $global:WaitingForLoop  = $false
                    if ($global:Queue.Count -eq 1) {
                        Write-Host "  Replaying song..." -ForegroundColor Green
                    } else {
                        Write-Host "  Looping queue from start!" -ForegroundColor Green
                    }
                    Play-Current
                    return
                }
                if ($k -eq "X") {
                    Write-Host ""
                    Stop-Current
                    $global:Running        = $false
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
    $global:Running        = $false
    $global:WaitingForLoop = $false
}

# Initialize
$global:LoopMode        = $false
$global:RepeatOne       = $false
$global:Paused          = $false
$global:Running         = $true
$global:WaitingForLoop  = $false
$global:Volume          = 100
$global:SearchMode      = $false
$global:PreSearchQueue  = $null
$global:CursorIndex     = 0
$global:LastPlayedIndex = 0
$global:QueueOpen       = $false
$global:PreSearchFile = $null

Shuffle-Queue

if ($global:CliSongTarget) {
    $global:PreSearchQueue = $global:Queue
    $foundAt = [array]::IndexOf($global:Queue, $global:CliSongTarget)   
    $global:SearchMode     = $true
    $global:Queue          = @($global:CliSongTarget)
    $global:Index          = 0
    $global:LoopMode       = $false
    $global:RepeatOne      = $false
    Write-Host "  [Search mode: playing single song]" -ForegroundColor DarkYellow
}

Show-Queue
Play-Current

Write-Host "Controls:"
Write-Host "  N = Next       | B = Previous  | P = Pause/Play"
Write-Host "  S = Shuffle    | Q = View Queue | QQ = Navigate | F = Search"
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

        if ($global:QueueOpen) {
            switch ($key) {
                "Q" {
                    $global:QueueOpen = $false
                    Open-Navigator
                }
                default {
                    $global:QueueOpen = $false
                    Write-Host ""
                    switch ($key) {
                        "N"        { Next-Track }
                        "B"        { Prev-Track }
                        "P"        { Toggle-Pause }
                        "S"        {



                            if ($global:SearchMode) { Exit-SearchMode }
                            Write-Host "`n  Shuffling..." -ForegroundColor Yellow
                            Stop-Current
                            Shuffle-Queue
                            Show-Queue
                            Play-Current
                        }
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
                        "UpArrow"   { }
                        "DownArrow" { }
                    }
                }
            }

        } else {
            switch ($key) {
                "N"        { Write-Host ""; Next-Track }
                "B"        { Write-Host ""; Prev-Track }
                "P"        { Toggle-Pause }
                "S"        {



                    if ($global:SearchMode) { Exit-SearchMode }
                    Write-Host "`n  Shuffling..." -ForegroundColor Yellow
                    Stop-Current
                    Shuffle-Queue
                    Show-Queue
                    Play-Current
                }
                "Q"        {
                    $global:QueueOpen   = $true
                    $global:CursorIndex = $global:Index
                    Write-Host ""
                    Show-Queue
                }
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
                "UpArrow"   { }
                "DownArrow" { }
            }
        }
    }

    # Auto-next when song ends
    if (-not $global:WaitingForLoop -and $global:Alias) {
        $status = New-Object System.Text.StringBuilder 128
        [WinMM]::mciSendString("status $global:Alias mode", $status, 128, [IntPtr]::Zero) | Out-Null

        if ($status.ToString() -eq "stopped" -and -not $global:Paused) {
            if ($global:RepeatOne) {
                $global:LastPlayedIndex = $global:Index
                Stop-Current
                Play-Current
            } elseif ($global:Index + 1 -ge $global:Queue.Count) {
                if ($global:LoopMode) {
                    $global:LastPlayedIndex = $global:Index
                    Write-Host "`n  Restarting queue..." -ForegroundColor DarkCyan
                    $global:Index = 0
                    Play-Current
                } else {
                    Start-EndOfQueueCountdown
                }
            } else {
                $global:LastPlayedIndex = $global:Index
                $global:Index++
                Play-Current
            }
        }
    }

    Start-Sleep -Milliseconds 200
}
