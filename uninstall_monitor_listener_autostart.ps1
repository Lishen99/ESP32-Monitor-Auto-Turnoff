$ErrorActionPreference = "Stop"

$taskName = "ESP32MonitorAutoTurnoffListener"
$startupLauncher = Join-Path ([Environment]::GetFolderPath("Startup")) "ESP32MonitorAutoTurnoffListener.cmd"
$workspace = Split-Path -Parent $MyInvocation.MyCommand.Path
$listenerPath = Join-Path $workspace "monitor_presence_listener.py"

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Removed task: $taskName"
} else {
    Write-Host "Task not found: $taskName"
}

if (Test-Path $startupLauncher) {
    Remove-Item $startupLauncher -Force
    Write-Host "Removed Startup launcher: $startupLauncher"
} else {
    Write-Host "Startup launcher not found: $startupLauncher"
}

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

if ($processes) {
    foreach ($process in $processes) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        Write-Host "Stopped listener process PID: $($process.ProcessId)"
    }
} else {
    Write-Host "No running listener process found."
}
