# Instalar Monitor Data Sync como Windows Service
# Execute como ADMINISTRADOR no servidor

param(
    [switch]$Remover
)

$nomeServico = "DataSyncMonitor"
$descricaoServico = "Monitor Data Sync em tempo real - Alertas de falha"
$caminhoScript = "C:\Users\Datasync\Desktop\monitor-datasync-continuo.ps1"
$arquivoNSSM = "$env:ProgramFiles\nssm\nssm.exe"

Write-Host "════════════════════════════════════════════════"
Write-Host "CONFIGURAR MONITOR COMO WINDOWS SERVICE"
Write-Host "════════════════════════════════════════════════"
Write-Host ""

# Verificar se é administrador
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
if(-not $isAdmin) {
    Write-Host "ERRO: Execute como ADMINISTRADOR!"
    exit 1
}

if($Remover) {
    Write-Host "Removendo serviço $nomeServico..."

    # Parar serviço
    Stop-Service -Name $nomeServico -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Remover serviço
    if(Test-Path $arquivoNSSM) {
        & $arquivoNSSM remove $nomeServico confirm
    } else {
        sc.exe delete $nomeServico
    }

    Write-Host "Serviço removido!"
    exit 0
}

# Verificar se NSSM existe
if(-not (Test-Path $arquivoNSSM)) {
    Write-Host "NSSM nao encontrado em: $arquivoNSSM"
    Write-Host ""
    Write-Host "OPÇÕES:"
    Write-Host "1. Baixar NSSM: https://nssm.cc/download"
    Write-Host "   Extrair para: C:\Program Files\nssm\"
    Write-Host ""
    Write-Host "2. Ou usar método alternativo (PowerShell puro):"
    Write-Host "   Criar tarefa agendada que roda ao iniciar"
    Write-Host ""

    # Oferecer alternativa com tarefa agendada
    Write-Host "Criando alternativa com Tarefa Agendada..."

    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit 0 -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -NoProfile -File `"$caminhoScript`""

    $task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description $descricaoServico

    Register-ScheduledTask -TaskName $nomeServico -InputObject $task -Force

    Write-Host ""
    Write-Host "════════════════════════════════════════════════"
    Write-Host "TAREFA AGENDADA CRIADA!"
    Write-Host "════════════════════════════════════════════════"
    Write-Host "Nome: $nomeServico"
    Write-Host "Descricao: $descricaoServico"
    Write-Host "Acionador: Ao iniciar o sistema"
    Write-Host "Executa como: SYSTEM (maxima prioridade)"
    Write-Host ""
    Write-Host "Monitor iniciara automaticamente na proxima reinicializacao"
    Write-Host "Ou inicie agora: Start-ScheduledTask -TaskName '$nomeServico'"
    Write-Host ""

    exit 0
}

# Se NSSM existe, usar ele (mais robusto)
Write-Host "🔧 Usando NSSM para criar serviço..."
Write-Host ""

# Verificar se serviço já existe
$servicoExistente = Get-Service -Name $nomeServico -ErrorAction SilentlyContinue
if($servicoExistente) {
    Write-Host "⚠️ Serviço já existe. Removendo..."
    Stop-Service -Name $nomeServico -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    & $arquivoNSSM remove $nomeServico confirm
    Start-Sleep -Seconds 1
}

# Criar serviço
Write-Host "Registrando serviço com NSSM..."
& $arquivoNSSM install $nomeServico "powershell.exe" "-ExecutionPolicy Bypass -NoProfile -File `"$caminhoScript`""

# Configurar serviço
& $arquivoNSSM set $nomeServico AppDirectory "C:\Users\Datasync\Desktop"
& $arquivoNSSM set $nomeServico AppStdout "C:\Logs\DataSync\monitor.log"
& $arquivoNSSM set $nomeServico AppStderr "C:\Logs\DataSync\monitor-erro.log"
& $arquivoNSSM set $nomeServico Description $descricaoServico
& $arquivoNSSM set $nomeServico Start SERVICE_AUTO_START
& $arquivoNSSM set $nomeServico Type SERVICE_WIN32_OWN_PROCESS
& $arquivoNSSM set $nomeServico ObjectName "LocalSystem"

# Iniciar serviço
Write-Host ""
Write-Host "Iniciando serviço..."
Start-Service -Name $nomeServico

Start-Sleep -Seconds 2

# Verificar status
$status = Get-Service -Name $nomeServico
if($status.Status -eq "Running") {
    Write-Host ""
    Write-Host "════════════════════════════════════════════════"
    Write-Host "SERVICO CRIADO E INICIADO COM SUCESSO!"
    Write-Host "════════════════════════════════════════════════"
    Write-Host "Nome: $nomeServico"
    Write-Host "Status: Rodando"
    Write-Host "Inicio: Automatico (ao iniciar o servidor)"
    Write-Host "Logs: C:\Logs\DataSync\monitor.log"
    Write-Host ""
    Write-Host "Comandos uteis:"
    Write-Host "  Parar:  Stop-Service -Name $nomeServico"
    Write-Host "  Iniciar: Start-Service -Name $nomeServico"
    Write-Host "  Status: Get-Service -Name $nomeServico"
    Write-Host "  Remover: powershell -File instalar-servico-datasync.ps1 -Remover"
    Write-Host "════════════════════════════════════════════════"
} else {
    Write-Host ""
    Write-Host "Erro ao iniciar servico"
    Write-Host "Status: $($status.Status)"
}
