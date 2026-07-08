# ATUALIZAR - servidor-painel-http.ps1 no servidor 192.168.0.147
# Envia so o arquivo corrigido e reinicia o DataSyncHTTP. Nao mexe na
# credencial do painel de vendas (ja salva).
# Execute com: powershell -ExecutionPolicy Bypass -File "atualizar-servidor-http.ps1"

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host " ATUALIZAR - servidor-painel-http.ps1" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TiDir = Split-Path -Parent $ScriptDir

Write-Host "Usuario Datasync no servidor 192.168.0.147:" -ForegroundColor Yellow
$senhaServidor = Read-Host "Senha do usuario Datasync" -AsSecureString
$credServidor = New-Object System.Management.Automation.PSCredential("Datasync", $senhaServidor)

$servidorHttp = Get-Content "$TiDir\servidor-painel-http.ps1" -Raw -Encoding UTF8

Write-Host "Conectando ao servidor..." -ForegroundColor Cyan
$session = New-PSSession -ComputerName 192.168.0.147 -Credential $credServidor -ErrorAction Stop

Invoke-Command -Session $session -ScriptBlock {
    param($servidorHttp)

    $tiDir = "C:\Users\Datasync\Desktop\ti"
    $utf8  = [System.Text.UTF8Encoding]::new($true)
    [System.IO.File]::WriteAllText("$tiDir\servidor-painel-http.ps1", $servidorHttp, $utf8)
    Write-Host "[OK] servidor-painel-http.ps1 atualizado" -ForegroundColor Green

    Write-Host "Matando processo antigo do servidor HTTP (se existir)..." -ForegroundColor Cyan
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -like "*servidor-painel-http*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    Stop-ScheduledTask -TaskName "DataSyncHTTP" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Start-ScheduledTask -TaskName "DataSyncHTTP"
    Start-Sleep -Seconds 3

    $tarefa = Get-ScheduledTask -TaskName "DataSyncHTTP"
    Write-Host "[OK] DataSyncHTTP - Estado: $($tarefa.State)" -ForegroundColor Green
} -ArgumentList $servidorHttp

Remove-PSSession $session

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host " ATUALIZACAO CONCLUIDA! Teste: http://192.168.0.147:8080/vendas.html" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
pause
