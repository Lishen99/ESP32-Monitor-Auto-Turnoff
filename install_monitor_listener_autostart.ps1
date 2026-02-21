$ErrorActionPreference = "Stop"

$taskName = "ESP32MonitorAutoTurnoffListener"
$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path $workspace "monitor_presence_listener.py"

if (-not (Test-Path $scriptPath)) {
    throw "monitor_presence_listener.py not found at $scriptPath"
}

$pywCmd = Get-Command pyw.exe -ErrorAction SilentlyContinue
if (-not $pywCmd) {
    throw "pyw.exe not found. Install Python with the Windows launcher."
}

function Get-ListenerProcess {
    param([string]$TargetScriptPath)

    $escapedPath = [Regex]::Escape($TargetScriptPath)
    Get-CimInstance Win32_Process |
        Where-Object {
            ($_.Name -in @("python.exe", "pyw.exe")) -and
            $_.CommandLine -and
            (
                $_.CommandLine -match "monitor_presence_listener\.py" -or
                $_.CommandLine -match "listener\.py" -or
                $_.CommandLine -match $escapedPath
            )
        }
}

function Start-ListenerIfNeeded {
    param(
        [string]$PythonPath,
        [string]$TargetScriptPath,
        [string]$WorkingDir
    )

    $existing = Get-ListenerProcess -TargetScriptPath $TargetScriptPath
    if ($existing) {
        $legacy = $existing | Where-Object { $_.CommandLine -match "listener\.py" -and $_.CommandLine -notmatch "monitor_presence_listener\.py" }
        if ($legacy) {
            foreach ($process in $legacy) {
                Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
                Write-Host "Stopped legacy listener process PID: $($process.ProcessId)"
            }
            Start-Sleep -Milliseconds 200
        }
        else {
            $pidList = ($existing | Select-Object -ExpandProperty ProcessId) -join ", "
            Write-Host "Listener already running (PID: $pidList)"
            return
        }
    }

    Start-Process -FilePath $PythonPath -ArgumentList "-3", "`"$TargetScriptPath`"", "--background" -WorkingDirectory $WorkingDir -WindowStyle Hidden
    Start-Sleep -Milliseconds 400

    $started = Get-ListenerProcess -TargetScriptPath $TargetScriptPath
    if ($started) {
        $pidList = ($started | Select-Object -ExpandProperty ProcessId) -join ", "
        Write-Host "Started listener now (PID: $pidList)"
    }
    else {
        Write-Host "Could not confirm listener startup. Check listener.log"
    }
}

try {
    $action = New-ScheduledTaskAction -Execute $pywCmd.Source -Argument "-3 `"$scriptPath`" --background" -WorkingDirectory $workspace
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "ESP32 monitor auto on/off listener" -User $env:USERNAME -RunLevel Limited -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName

    Write-Host "Installed autostart task: $taskName"
    Write-Host "It will run hidden at login and logs to listener.log"
    Start-ListenerIfNeeded -PythonPath $pywCmd.Source -TargetScriptPath $scriptPath -WorkingDir $workspace
}
catch {
    $startupFolder = [Environment]::GetFolderPath("Startup")
    $launcherPath = Join-Path $startupFolder "ESP32MonitorAutoTurnoffListener.cmd"
    $launcherContent = "@echo off`r`n`"$($pywCmd.Source)`" -3 `"$scriptPath`" --background`r`n"
    Set-Content -Path $launcherPath -Value $launcherContent -Encoding ASCII

    Write-Host "Task Scheduler registration failed. Installed Startup launcher instead:"
    Write-Host $launcherPath
    Write-Host "It will run hidden at login and logs to listener.log"
    Start-ListenerIfNeeded -PythonPath $pywCmd.Source -TargetScriptPath $scriptPath -WorkingDir $workspace
}
