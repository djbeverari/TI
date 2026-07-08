#Requires -RunAsAdministrator

$scriptPath = Join-Path $PSScriptRoot "gera-painel-negativos.ps1"

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

$trigger = New-ScheduledTaskTrigger -Weekly `
    -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday `
    -At "11:05AM"

Register-ScheduledTask -TaskName "PainelEstoqueNegativos" `
    -Action $action -Trigger $trigger `
    -Description "Gera o painel HTML de estoque negativo a partir da retaguarda" `
    -RunLevel Highest -Force -ErrorAction Stop

Write-Host "Tarefa 'PainelEstoqueNegativos' registrada: seg-sex as 11:05."
