param(
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"

$taskName = "ESP32MonitorAutoTurnoffListener"
$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$listenerPath = Join-Path $workspace "monitor_presence_listener.py"
$startupLauncher = Join-Path ([Environment]::GetFolderPath("Startup")) "ESP32MonitorAutoTurnoffListener.cmd"
$logPath = Join-Path $workspace "listener.log"

$taskExists = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
$escapedListenerPath = [Regex]::Escape($listenerPath)
$processes = Get-CimInstance Win32_Process |
    Where-Object {
        ($_.Name -in @("python.exe", "pyw.exe")) -and
        $_.CommandLine -and
        (
            $_.CommandLine -match "monitor_presence_listener\.py" -or
            $_.CommandLine -match "listener\.py" -or
            $_.CommandLine -match $escapedListenerPath
        )
    }

Write-Host "=== ESP32 Monitor Listener Status ==="
Write-Host "Workspace: $workspace"
Write-Host "Listener path: $listenerPath"

if ($taskExists) {
    $taskState = (Get-ScheduledTask -TaskName $taskName).State
    Write-Host "Autostart mode: Task Scheduler ($taskName)"
    Write-Host "Task state: $taskState"
}
elseif (Test-Path $startupLauncher) {
    Write-Host "Autostart mode: Startup launcher"
    Write-Host "Launcher: $startupLauncher"
}
else {
    Write-Host "Autostart mode: Not installed"
}

if ($processes) {
    $pidList = ($processes | Select-Object -ExpandProperty ProcessId) -join ", "
    Write-Host "Running: Yes"
    Write-Host "PID(s): $pidList"
}
else {
    Write-Host "Running: No"
}

if (Test-Path $logPath) {
    Write-Host "Log file: $logPath"
    Write-Host "Last 5 log lines:"
    Get-Content -Path $logPath -Tail 5
}
else {
    Write-Host "Log file not found: $logPath"
}

if (-not $NoPause -and $Host.Name -eq "ConsoleHost") {
    Write-Host ""
    Read-Host "Press Enter to close"
}
