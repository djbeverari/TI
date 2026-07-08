# Pausar todos os agendamentos Data Sync
# Desabilita as 3 tasks do Task Scheduler

Write-Host ""
Write-Host "════════════════════════════════════════════════"
Write-Host "⏸️ PAUSANDO AGENDAMENTOS DATA SYNC"
Write-Host "════════════════════════════════════════════════"
Write-Host ""

$tasks = @(
    "DataSync_1030",
    "DataSync_1430",
    "DataSync_1630"
)

foreach($task in $tasks) {
    try {
        Write-Host "Desabilitando: $task..."
        Disable-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
        Write-Host "✅ $task desabilitado"
    } catch {
        Write-Host "⚠️ Erro ao desabilitar $task"
    }
}

Write-Host ""
Write-Host "════════════════════════════════════════════════"
Write-Host "⏸️ AGENDAMENTOS PAUSADOS"
Write-Host ""
Write-Host "Para retomar, execute:"
Write-Host "  & 'C:\Users\Daniella\ti\retomar-agendamentos.ps1'"
Write-Host "════════════════════════════════════════════════"
Write-Host ""
