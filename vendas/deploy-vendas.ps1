# DEPLOY - Painel de Vendas no servidor 192.168.0.147
# Execute com: powershell -ExecutionPolicy Bypass -File "deploy-vendas.ps1"
# Precisa rodar interativamente (pede duas senhas: acesso ao servidor e SQL da retaguarda)

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host " DEPLOY - Painel de Vendas no servidor 192.168.0.147" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Usuario Datasync no servidor 192.168.0.147:" -ForegroundColor Yellow
$senhaServidor = Read-Host "Senha do usuario Datasync" -AsSecureString
$credServidor = New-Object System.Management.Automation.PSCredential("Datasync", $senhaServidor)

Write-Host ""
Write-Host "Credencial SQL da retaguarda (Dorinhos_2022 @ 192.168.0.55) - sera salva no servidor:" -ForegroundColor Yellow
$usuarioRetaguarda = Read-Host "Usuario SQL (ex: sa)"
$senhaRetaguarda = Read-Host "Senha SQL da retaguarda" -AsSecureString
$credRetaguarda = New-Object System.Management.Automation.PSCredential($usuarioRetaguarda, $senhaRetaguarda)

Write-Host "Conectando ao servidor..." -ForegroundColor Cyan
$session = New-PSSession -ComputerName 192.168.0.147 -Credential $credServidor -ErrorAction Stop

$conexao   = Get-Content "$ScriptDir\conexao-retaguarda.ps1"   -Raw -Encoding UTF8
$vendasLib = Get-Content "$ScriptDir\vendas-lib.ps1"           -Raw -Encoding UTF8
$queries   = Get-Content "$ScriptDir\vendas-queries.ps1"       -Raw -Encoding UTF8
$gerador   = Get-Content "$ScriptDir\gerar-painel-vendas.ps1"  -Raw -Encoding UTF8

Write-Host "Conectado. Enviando arquivos..." -ForegroundColor Green

Invoke-Command -Session $session -ScriptBlock {
    param($conexao, $vendasLib, $queries, $gerador, $credRetaguarda)

    $vendasDir = "C:\Users\Datasync\Desktop\ti\vendas"
    if (-not (Test-Path $vendasDir)) {
        New-Item -ItemType Directory -Path $vendasDir -Force | Out-Null
    }
    $utf8 = [System.Text.UTF8Encoding]::new($true)

    [System.IO.File]::WriteAllText("$vendasDir\conexao-retaguarda.ps1",  $conexao,   $utf8)
    [System.IO.File]::WriteAllText("$vendasDir\vendas-lib.ps1",          $vendasLib, $utf8)
    [System.IO.File]::WriteAllText("$vendasDir\vendas-queries.ps1",      $queries,   $utf8)
    [System.IO.File]::WriteAllText("$vendasDir\gerar-painel-vendas.ps1", $gerador,   $utf8)
    Write-Host "[OK] Scripts copiados para $vendasDir" -ForegroundColor Green

    $credRetaguarda | Export-Clixml -Path "$vendasDir\.sql_cred_retaguarda" -Force
    Write-Host "[OK] Credencial SQL da retaguarda salva (DPAPI, usuario Datasync)" -ForegroundColor Green

    # Testar geracao do painel
    & "$vendasDir\gerar-painel-vendas.ps1"

    if (Test-Path "C:\Logs\DataSync\vendas.html") {
        Write-Host "[OK] vendas.html gerado: $((Get-Item 'C:\Logs\DataSync\vendas.html').LastWriteTime)" -ForegroundColor Green
    } else {
        Write-Host "[FALHOU] vendas.html nao foi gerado" -ForegroundColor Red
    }

    # Agendar tarefa diaria as 11:30
    $acao = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$vendasDir\gerar-painel-vendas.ps1`""
    $gatilho = New-ScheduledTaskTrigger -Daily -At 11:30AM
    Register-ScheduledTask -TaskName 'PainelVendas' `
        -Action $acao -Trigger $gatilho `
        -Description 'Gera o painel de vendas da rede diariamente as 11:30' `
        -User 'Datasync' -RunLevel Highest -Force | Out-Null

    $tarefa = Get-ScheduledTask -TaskName 'PainelVendas'
    Write-Host "[OK] Tarefa 'PainelVendas' agendada - Estado: $($tarefa.State)" -ForegroundColor Green

} -ArgumentList $conexao, $vendasLib, $queries, $gerador, $credRetaguarda

Remove-PSSession $session

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host " DEPLOY CONCLUIDO!" -ForegroundColor Green
Write-Host " Painel: http://192.168.0.147:8080/vendas.html" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
pause
