#Requires -RunAsAdministrator

param(
    [int]$Porta = 8081
)

$webDir = Join-Path $PSScriptRoot "web"
if (-not (Test-Path $webDir)) {
    New-Item -ItemType Directory -Path $webDir -Force | Out-Null
}

$python = (Get-Command python).Source
$action = New-ScheduledTaskAction -Execute $python `
    -Argument "-m http.server $Porta --directory `"$webDir`"" `
    -WorkingDirectory $webDir

$trigger = New-ScheduledTaskTrigger -AtLogOn

Register-ScheduledTask -TaskName "PainelEstoqueNegativosWeb" `
    -Action $action -Trigger $trigger `
    -Description "Sobe o http.server do painel de estoque negativos na porta $Porta" `
    -RunLevel Highest -Force -ErrorAction Stop

Write-Host "Tarefa 'PainelEstoqueNegativosWeb' registrada: inicia http.server na porta $Porta ao logar."
