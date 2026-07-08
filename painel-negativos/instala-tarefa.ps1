#Requires -RunAsAdministrator

$scriptPath = Join-Path $PSScriptRoot "gera-painel-negativos.ps1"

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

$trigger = New-ScheduledTaskTrigger -Weekly `
    -DaysOfWeek Friday `
    -At "13:00"

Register-ScheduledTask -TaskName "PainelEstoqueNegativos" `
    -Action $action -Trigger $trigger `
    -Description "Gera o painel HTML de estoque negativo a partir da retaguarda" `
    -RunLevel Highest -Force -ErrorAction Stop

Write-Host "Tarefa 'PainelEstoqueNegativos' registrada: sexta-feira as 13:00."
