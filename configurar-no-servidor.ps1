# ============================================================
# CONFIGURAR DATA SYNC NO SERVIDOR - Execute como ADMINISTRADOR
# Servidor: 192.168.0.147 | Usuario: Datasync
# ============================================================
#
# INSTRUCOES:
#   1. Copie a pasta "ti" inteira para a area de trabalho do servidor
#      Ex: C:\Users\Datasync\Desktop\ti\
#   2. Execute este script como ADMINISTRADOR no servidor
#   3. Apos executar, acesse o painel em: http://192.168.0.147:8080/painel.html
# ============================================================

param(
    [switch]$Remover
)

$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogPath      = "C:\Logs\DataSync"
$DesktopPath  = "C:\Users\Datasync\Desktop"
$CredPath     = "$DesktopPath\ti\.email_cred"

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host " CONFIGURAR DATA SYNC - SERVIDOR" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

# Verificar se eh administrador
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
if (-not $isAdmin) {
    Write-Host "ERRO: Execute como ADMINISTRADOR!" -ForegroundColor Red
    Write-Host "Clique com botao direito no PowerShell > Executar como administrador" -ForegroundColor Yellow
    pause
    exit 1
}

# ---- MODO REMOVER ----
if ($Remover) {
    Write-Host "Removendo tarefas agendadas..." -ForegroundColor Yellow
    "DataSync_1030","DataSync_1430","DataSync_1630","DataSyncPainel","DataSyncHTTP" | ForEach-Object {
        Unregister-ScheduledTask -TaskName $_ -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "  Removida: $_" -ForegroundColor Gray
    }
    Write-Host "Tarefas removidas." -ForegroundColor Green
    exit 0
}

# ---- VERIFICAR ARQUIVOS ----
Write-Host "Verificando arquivos necessarios..." -ForegroundColor Cyan

$arquivosNecessarios = @(
    "$ScriptDir\data-sync-automacao.ps1",
    "$ScriptDir\gerar-painel-datasync.ps1",
    "$ScriptDir\servidor-painel-http.ps1"
)

$ok = $true
foreach ($arq in $arquivosNecessarios) {
    if (Test-Path $arq) {
        Write-Host "  [OK] $arq" -ForegroundColor Green
    } else {
        Write-Host "  [FALTA] $arq" -ForegroundColor Red
        $ok = $false
    }
}

if (-not $ok) {
    Write-Host ""
    Write-Host "ERRO: Arquivos faltando. Copie a pasta 'ti' completa para o servidor." -ForegroundColor Red
    pause
    exit 1
}

# ---- CRIAR PASTAS ----
Write-Host ""
Write-Host "Criando pastas necessarias..." -ForegroundColor Cyan

@($LogPath, "$DesktopPath\DATA SYNC SERVER") | ForEach-Object {
    if (!(Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
        Write-Host "  Criada: $_" -ForegroundColor Green
    } else {
        Write-Host "  Existe: $_" -ForegroundColor Gray
    }
}

# ---- COPIAR SCRIPTS ----
Write-Host ""
Write-Host "Copiando scripts para $DesktopPath\ti\..." -ForegroundColor Cyan

$tiDest = "$DesktopPath\ti"
if (!(Test-Path $tiDest)) { New-Item -ItemType Directory -Path $tiDest -Force | Out-Null }

Copy-Item "$ScriptDir\data-sync-automacao.ps1"    "$tiDest\" -Force
Copy-Item "$ScriptDir\gerar-painel-datasync.ps1"  "$tiDest\" -Force
Copy-Item "$ScriptDir\servidor-painel-http.ps1"   "$tiDest\" -Force
Copy-Item "$ScriptDir\guardar-senha-email.ps1"    "$tiDest\" -Force -ErrorAction SilentlyContinue

Write-Host "  Scripts copiados." -ForegroundColor Green

# ---- CORRIGIR PATH DA CREDENCIAL DE EMAIL NO SCRIPT ----
$syncScript = "$tiDest\data-sync-automacao.ps1"
$conteudo = Get-Content $syncScript -Raw -Encoding UTF8
$conteudo = $conteudo -replace '\$ArquivoCredencial = ".+?"', "`$ArquivoCredencial = `"$CredPath`""
[System.IO.File]::WriteAllText($syncScript, $conteudo, [System.Text.UTF8Encoding]::new($false))
Write-Host "  Path de credencial de email ajustado." -ForegroundColor Green

# ---- CRIAR TAREFAS AGENDADAS ----
Write-Host ""
Write-Host "Criando tarefas agendadas..." -ForegroundColor Cyan

$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit 0

# DataSync 10:30
$action   = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$tiDest\data-sync-automacao.ps1`""
$trigger  = New-ScheduledTaskTrigger -Daily -At "10:30" -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday 2>$null
if (-not $trigger) { $trigger = New-ScheduledTaskTrigger -Daily -At "10:30" }
Unregister-ScheduledTask -TaskName "DataSync_1030" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "DataSync_1030" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Data Sync 10:30" -Force | Out-Null
Write-Host "  [OK] DataSync_1030 (10:30)" -ForegroundColor Green

# DataSync 14:30
$trigger  = New-ScheduledTaskTrigger -Daily -At "14:30"
Unregister-ScheduledTask -TaskName "DataSync_1430" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "DataSync_1430" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Data Sync 14:30" -Force | Out-Null
Write-Host "  [OK] DataSync_1430 (14:30)" -ForegroundColor Green

# DataSync 16:30
$trigger  = New-ScheduledTaskTrigger -Daily -At "16:30"
Unregister-ScheduledTask -TaskName "DataSync_1630" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "DataSync_1630" -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "Data Sync 16:30" -Force | Out-Null
Write-Host "  [OK] DataSync_1630 (16:30)" -ForegroundColor Green

# DataSyncPainel - Gerar painel (inicia com o sistema)
$actionPainel = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$tiDest\gerar-painel-datasync.ps1`""
$triggerPainel = New-ScheduledTaskTrigger -AtStartup
$settingsPainel = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit 0 -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 2)
Unregister-ScheduledTask -TaskName "DataSyncPainel" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "DataSyncPainel" -Action $actionPainel -Trigger $triggerPainel -Principal $principal -Settings $settingsPainel -Description "Gerador de painel HTML Data Sync" -Force | Out-Null
Write-Host "  [OK] DataSyncPainel (inicio do sistema)" -ForegroundColor Green

# DataSyncHTTP - Servidor HTTP para o painel (inicia com o sistema)
$actionHTTP = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$tiDest\servidor-painel-http.ps1`" -Porta 8080 -PastaLogs `"$LogPath`""
$triggerHTTP = New-ScheduledTaskTrigger -AtStartup
$settingsHTTP = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit 0 -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 2)
Unregister-ScheduledTask -TaskName "DataSyncHTTP" -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName "DataSyncHTTP" -Action $actionHTTP -Trigger $triggerHTTP -Principal $principal -Settings $settingsHTTP -Description "Servidor HTTP - Painel Data Sync" -Force | Out-Null
Write-Host "  [OK] DataSyncHTTP - Porta 8080 (inicio do sistema)" -ForegroundColor Green

# ---- ABRIR PORTA NO FIREWALL ----
Write-Host ""
Write-Host "Configurando firewall para porta 8080..." -ForegroundColor Cyan

$regraExistente = Get-NetFirewallRule -DisplayName "DataSync Painel HTTP" -ErrorAction SilentlyContinue
if (-not $regraExistente) {
    New-NetFirewallRule -DisplayName "DataSync Painel HTTP" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow | Out-Null
    Write-Host "  [OK] Regra de firewall criada (porta 8080 TCP entrada)" -ForegroundColor Green
} else {
    Write-Host "  Regra de firewall ja existe." -ForegroundColor Gray
}

# ---- INICIAR SERVICOS IMEDIATAMENTE ----
Write-Host ""
Write-Host "Iniciando tarefas agora..." -ForegroundColor Cyan

Start-ScheduledTask -TaskName "DataSyncPainel" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
Start-ScheduledTask -TaskName "DataSyncHTTP" -ErrorAction SilentlyContinue

Write-Host "  [OK] DataSyncPainel iniciado" -ForegroundColor Green
Write-Host "  [OK] DataSyncHTTP iniciado" -ForegroundColor Green

# ---- RESULTADO ----
Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host " CONFIGURACAO CONCLUIDA!" -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Tarefas agendadas:" -ForegroundColor Yellow
Write-Host "  DataSync_1030  - Sincronizacao 10:30 (seg a sex)" -ForegroundColor White
Write-Host "  DataSync_1430  - Sincronizacao 14:30 (seg a sex)" -ForegroundColor White
Write-Host "  DataSync_1630  - Sincronizacao 16:30 (seg a sex)" -ForegroundColor White
Write-Host "  DataSyncPainel - Gerador HTML (inicia com o sistema)" -ForegroundColor White
Write-Host "  DataSyncHTTP   - Servidor HTTP (inicia com o sistema)" -ForegroundColor White
Write-Host ""
Write-Host "Painel de monitoramento:" -ForegroundColor Yellow
Write-Host "  http://192.168.0.147:8080/painel.html" -ForegroundColor Cyan
Write-Host "  (Acessivel de qualquer maquina da rede)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Credenciais de email:" -ForegroundColor Yellow
Write-Host "  Execute para salvar senha: $tiDest\guardar-senha-email.ps1" -ForegroundColor White
Write-Host ""
Write-Host "Para remover tudo:" -ForegroundColor Yellow
Write-Host "  powershell -File configurar-no-servidor.ps1 -Remover" -ForegroundColor White
Write-Host ""

pause
