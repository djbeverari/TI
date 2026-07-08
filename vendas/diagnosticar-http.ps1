# DIAGNOSTICO (somente leitura) - Servidor HTTP (DataSyncHTTP) no servidor 192.168.0.147
# Execute com: powershell -ExecutionPolicy Bypass -File "diagnosticar-http.ps1"
# Nao reinicia nada - so mostra o estado atual. Para reiniciar, veja
# reiniciar-servidor-http.ps1 (separado, so rode se decidir reiniciar).

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host " DIAGNOSTICO (leitura) - Servidor HTTP (DataSyncHTTP)" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Usuario Datasync no servidor 192.168.0.147:" -ForegroundColor Yellow
$senhaServidor = Read-Host "Senha do usuario Datasync" -AsSecureString
$credServidor = New-Object System.Management.Automation.PSCredential("Datasync", $senhaServidor)

$session = New-PSSession -ComputerName 192.168.0.147 -Credential $credServidor -ErrorAction Stop

Invoke-Command -Session $session -ScriptBlock {
    Write-Host "=== 1. Estado da tarefa DataSyncHTTP ===" -ForegroundColor Cyan
    $tarefa = Get-ScheduledTask -TaskName "DataSyncHTTP" -ErrorAction SilentlyContinue
    $info = Get-ScheduledTaskInfo -TaskName "DataSyncHTTP" -ErrorAction SilentlyContinue
    if ($tarefa) {
        Write-Host "Estado: $($tarefa.State) | Ultima execucao: $($info.LastRunTime) | Ultimo resultado: $($info.LastTaskResult)" -ForegroundColor Green
    } else {
        Write-Host "Tarefa DataSyncHTTP nao encontrada!" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "=== 2. Processos powershell rodando o servidor HTTP ===" -ForegroundColor Cyan
    $procs = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object { $_.CommandLine -like "*servidor-painel-http*" }
    if ($procs) {
        $procs | Select-Object ProcessId, CreationDate, CommandLine | Format-List
    } else {
        Write-Host "NENHUM processo rodando servidor-painel-http.ps1!" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "=== 3. Porta 8080 em uso por qual processo? ===" -ForegroundColor Cyan
    Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue |
        Select-Object LocalAddress, State, OwningProcess | Format-Table -AutoSize

    Write-Host ""
    Write-Host "=== 4. Credencial do painel de vendas ===" -ForegroundColor Cyan
    $credPath = "C:\Users\Datasync\Desktop\ti\.painel_vendas_cred"
    if (Test-Path $credPath) {
        try {
            $cred = Import-Clixml -Path $credPath
            Write-Host "Credencial existe. Usuario salvo: $($cred.UserName)" -ForegroundColor Green
        } catch {
            Write-Host "ERRO ao ler credencial: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "Credencial NAO existe em $credPath" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "=== 5. Conteudo atual de servidor-painel-http.ps1 no servidor (primeiras linhas) ===" -ForegroundColor Cyan
    Get-Content "C:\Users\Datasync\Desktop\ti\servidor-painel-http.ps1" -TotalCount 15 -Encoding UTF8

    Write-Host ""
    Write-Host "=== 6. Log de debug (ultimas 10 linhas) ===" -ForegroundColor Cyan
    $debugLog = "C:\Users\Datasync\Desktop\ti\servidor-http-debug.log"
    if (Test-Path $debugLog) {
        Get-Content $debugLog -Tail 10 -Encoding UTF8
    } else {
        Write-Host "Log de debug ainda nao existe (nenhuma requisicao a vendas.html processada apos o deploy)." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "=== 7. Log de erros (ultimas 10 linhas) ===" -ForegroundColor Cyan
    $errosLog = "C:\Users\Datasync\Desktop\ti\servidor-http-erros.log"
    if (Test-Path $errosLog) {
        Get-Content $errosLog -Tail 10 -Encoding UTF8
    } else {
        Write-Host "Log de erros ainda nao existe." -ForegroundColor Yellow
    }
}

Remove-PSSession $session
Write-Host ""
Write-Host "Diagnostico concluido (nada foi alterado)." -ForegroundColor Cyan
pause
