# DEPLOY - Autenticacao (usuario/senha) no painel de vendas
# Execute com: powershell -ExecutionPolicy Bypass -File "deploy-auth-painel-vendas.ps1"
# Atualiza o servidor HTTP (servidor-painel-http.ps1) no 192.168.0.147 para
# exigir usuario/senha ao acessar vendas.html, e define essa senha.

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host " DEPLOY - Autenticacao do Painel de Vendas" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TiDir = Split-Path -Parent $ScriptDir

Write-Host "Usuario Datasync no servidor 192.168.0.147:" -ForegroundColor Yellow
$senhaServidor = Read-Host "Senha do usuario Datasync" -AsSecureString
$credServidor = New-Object System.Management.Automation.PSCredential("Datasync", $senhaServidor)

Write-Host ""
Write-Host "Defina o usuario/senha que vai proteger o painel de vendas (quem for acessar precisa disso):" -ForegroundColor Yellow
$usuarioPainel = Read-Host "Usuario de acesso ao painel de vendas"
$senhaPainel = Read-Host "Senha de acesso ao painel de vendas" -AsSecureString
$credPainel = New-Object System.Management.Automation.PSCredential($usuarioPainel, $senhaPainel)

Write-Host ""
Write-Host "Conectando ao servidor..." -ForegroundColor Cyan
$session = New-PSSession -ComputerName 192.168.0.147 -Credential $credServidor -ErrorAction Stop

$servidorHttp = Get-Content "$TiDir\servidor-painel-http.ps1" -Raw -Encoding UTF8

Write-Host "Conectado. Enviando servidor HTTP atualizado..." -ForegroundColor Green

Invoke-Command -Session $session -ScriptBlock {
    param($servidorHttp, $credPainel)

    $tiDir = "C:\Users\Datasync\Desktop\ti"
    $utf8  = [System.Text.UTF8Encoding]::new($true)

    [System.IO.File]::WriteAllText("$tiDir\servidor-painel-http.ps1", $servidorHttp, $utf8)
    Write-Host "[OK] servidor-painel-http.ps1 atualizado" -ForegroundColor Green

    $credPainel | Export-Clixml -Path "$tiDir\.painel_vendas_cred" -Force
    Write-Host "[OK] Credencial do painel de vendas salva (DPAPI, usuario Datasync)" -ForegroundColor Green

    Write-Host "Reiniciando DataSyncHTTP para carregar o novo codigo..." -ForegroundColor Cyan
    Stop-ScheduledTask -TaskName "DataSyncHTTP" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-ScheduledTask -TaskName "DataSyncHTTP"
    Start-Sleep -Seconds 3
    $tarefa = Get-ScheduledTask -TaskName "DataSyncHTTP"
    Write-Host "[OK] DataSyncHTTP - Estado: $($tarefa.State)" -ForegroundColor Green

} -ArgumentList $servidorHttp, $credPainel

Remove-PSSession $session

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host " DEPLOY CONCLUIDO!" -ForegroundColor Green
Write-Host " vendas.html agora pede usuario/senha." -ForegroundColor Cyan
Write-Host " Os outros paineis (painel.html, tickets.html) continuam sem senha." -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
pause
