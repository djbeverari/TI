# Retomar todos os agendamentos Data Sync
# Habilita as 3 tasks do Task Scheduler

Write-Host ""
Write-Host "════════════════════════════════════════════════"
Write-Host "▶️ RETOMANDO AGENDAMENTOS DATA SYNC"
Write-Host "════════════════════════════════════════════════"
Write-Host ""

$tasks = @(
    "DataSync_1030",
    "DataSync_1430",
    "DataSync_1630"
)

foreach($task in $tasks) {
    try {
        Write-Host "Habilitando: $task..."
        Enable-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
        Write-Host "✅ $task habilitado"
    } catch {
        Write-Host "⚠️ Erro ao habilitar $task"
    }
}

Write-Host ""
Write-Host "════════════════════════════════════════════════"
Write-Host "▶️ AGENDAMENTOS RETOMADOS"
Write-Host ""
Write-Host "Próximas execuções:"
Write-Host "  • 10:30"
Write-Host "  • 14:30"
Write-Host "  • 16:30"
Write-Host "════════════════════════════════════════════════"
Write-Host ""
