# REINICIAR - Servidor HTTP (DataSyncHTTP) no servidor 192.168.0.147
# Execute com: powershell -ExecutionPolicy Bypass -File "reiniciar-servidor-http.ps1"
#
# Autorizado pela Daniella em 2026-07-08 para corrigir vendas.html travando
# apos o deploy da autenticacao. Derruba e reinicia o servidor que serve
# TODOS os paineis (painel.html, tickets.html e vendas.html) - ficam
# indisponiveis por alguns segundos durante o reinicio.

Write-Host ""
Write-Host "================================================" -ForegroundColor Yellow
Write-Host " REINICIAR Servidor HTTP - afeta TODOS os paineis" -ForegroundColor Yellow
Write-Host " (painel.html, tickets.html, vendas.html ficam" -ForegroundColor Yellow
Write-Host " indisponiveis por alguns segundos)" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Yellow
Write-Host ""
$confirmacao = Read-Host "Digite SIM para confirmar o reinicio"
if ($confirmacao -ne "SIM") {
    Write-Host "Cancelado." -ForegroundColor Red
    pause
    exit 0
}

Write-Host ""
Write-Host "Usuario Datasync no servidor 192.168.0.147:" -ForegroundColor Yellow
$senhaServidor = Read-Host "Senha do usuario Datasync" -AsSecureString
$credServidor = New-Object System.Management.Automation.PSCredential("Datasync", $senhaServidor)

$session = New-PSSession -ComputerName 192.168.0.147 -Credential $credServidor -ErrorAction Stop

Invoke-Command -Session $session -ScriptBlock {
    Write-Host "Matando processos antigos do servidor HTTP (se existirem)..." -ForegroundColor Cyan
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -like "*servidor-painel-http*" } |
        ForEach-Object {
            Write-Host "Matando processo $($_.ProcessId)..." -ForegroundColor Yellow
            Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        }

    Stop-ScheduledTask -TaskName "DataSyncHTTP" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    Write-Host "Iniciando DataSyncHTTP..." -ForegroundColor Cyan
    Start-ScheduledTask -TaskName "DataSyncHTTP"
    Start-Sleep -Seconds 3

    $tarefa = Get-ScheduledTask -TaskName "DataSyncHTTP"
    Write-Host "Estado apos reinicio: $($tarefa.State)" -ForegroundColor Green
}

Remove-PSSession $session
Write-Host ""
Write-Host "Reinicio concluido. Teste: http://192.168.0.147:8080/vendas.html" -ForegroundColor Cyan
pause
