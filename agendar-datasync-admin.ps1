# ============================================================
# Agendar Data Sync - 3 Tarefas Diárias (EXECUTE COMO ADMIN)
# ============================================================

Write-Host "Criando tarefas agendadas para Data Sync..." -ForegroundColor Green

$ScriptPath = "C:\Users\Daniella\ti\data-sync-automacao.ps1"

# Criar ação (executar o script)
$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

# Tarefa 1: 10:30
Write-Host "Criando tarefa para 10:30..." -ForegroundColor Cyan
$Trigger1 = New-ScheduledTaskTrigger -Daily -At "10:30"
Register-ScheduledTask -TaskName "DataSync_1030" -Action $Action -Trigger $Trigger1 -RunLevel Highest -Force | Out-Null
Write-Host "✅ Tarefa 10:30 criada" -ForegroundColor Green

# Tarefa 2: 14:30
Write-Host "Criando tarefa para 14:30..." -ForegroundColor Cyan
$Trigger2 = New-ScheduledTaskTrigger -Daily -At "14:30"
Register-ScheduledTask -TaskName "DataSync_1430" -Action $Action -Trigger $Trigger2 -RunLevel Highest -Force | Out-Null
Write-Host "✅ Tarefa 14:30 criada" -ForegroundColor Green

# Tarefa 3: 16:30
Write-Host "Criando tarefa para 16:30..." -ForegroundColor Cyan
$Trigger3 = New-ScheduledTaskTrigger -Daily -At "16:30"
Register-ScheduledTask -TaskName "DataSync_1630" -Action $Action -Trigger $Trigger3 -RunLevel Highest -Force | Out-Null
Write-Host "✅ Tarefa 16:30 criada" -ForegroundColor Green

Write-Host "" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Green
Write-Host "✅ AGENDAMENTO CONCLUÍDO!" -ForegroundColor Green
Write-Host "════════════════════════════════════════" -ForegroundColor Green
Write-Host "" -ForegroundColor Cyan
Write-Host "3 tarefas criadas:" -ForegroundColor Yellow
Write-Host "  • DataSync_1030 (10:30)" -ForegroundColor White
Write-Host "  • DataSync_1430 (14:30)" -ForegroundColor White
Write-Host "  • DataSync_1630 (16:30)" -ForegroundColor White
Write-Host "" -ForegroundColor Cyan
Write-Host "Para verificar: Get-ScheduledTask -TaskName DataSync_*" -ForegroundColor Cyan
