# DIAGNOSTICO - Painel de Vendas no servidor 192.168.0.147
# Execute com: powershell -ExecutionPolicy Bypass -File "diagnosticar-vendas.ps1"

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host " DIAGNOSTICO - Painel de Vendas no servidor" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Usuario Datasync no servidor 192.168.0.147:" -ForegroundColor Yellow
$senhaServidor = Read-Host "Senha do usuario Datasync" -AsSecureString
$credServidor = New-Object System.Management.Automation.PSCredential("Datasync", $senhaServidor)

$session = New-PSSession -ComputerName 192.168.0.147 -Credential $credServidor -ErrorAction Stop

Invoke-Command -Session $session -ScriptBlock {
    $vendasDir = "C:\Users\Datasync\Desktop\ti\vendas"
    $destino   = "C:\Logs\DataSync\vendas.html"

    Write-Host "=== 1. Arquivos copiados existem? ===" -ForegroundColor Cyan
    @('conexao-retaguarda.ps1','vendas-lib.ps1','vendas-queries.ps1','gerar-painel-vendas.ps1','.sql_cred_retaguarda') | ForEach-Object {
        $caminho = Join-Path $vendasDir $_
        $existe = Test-Path $caminho
        Write-Host "$_ : $(if($existe){'OK'}else{'FALTANDO'})" -ForegroundColor $(if($existe){'Green'}else{'Red'})
    }

    Write-Host ""
    Write-Host "=== 2. vendas.html existe? ===" -ForegroundColor Cyan
    if (Test-Path $destino) {
        $item = Get-Item $destino
        Write-Host "Existe. Tamanho: $($item.Length) bytes. Modificado: $($item.LastWriteTime)" -ForegroundColor Green
    } else {
        Write-Host "NAO EXISTE em $destino" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "=== 3. Rodando gerar-painel-vendas.ps1 de novo, capturando erro completo ===" -ForegroundColor Cyan
    try {
        & "$vendasDir\gerar-painel-vendas.ps1" -ErrorAction Stop
        Write-Host "Rodou sem lancar excecao." -ForegroundColor Green
    } catch {
        Write-Host "ERRO: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack: $($_.ScriptStackTrace)" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "=== 4. vendas.html existe agora? ===" -ForegroundColor Cyan
    if (Test-Path $destino) {
        $item = Get-Item $destino
        Write-Host "Existe. Tamanho: $($item.Length) bytes. Modificado: $($item.LastWriteTime)" -ForegroundColor Green
    } else {
        Write-Host "AINDA NAO EXISTE em $destino" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "=== 5. Tarefa agendada PainelVendas ===" -ForegroundColor Cyan
    try {
        $tarefa = Get-ScheduledTask -TaskName 'PainelVendas' -ErrorAction Stop
        $info = Get-ScheduledTaskInfo -TaskName 'PainelVendas'
        Write-Host "Estado: $($tarefa.State) | Ultima execucao: $($info.LastRunTime) | Ultimo resultado: $($info.LastTaskResult)" -ForegroundColor Green
    } catch {
        Write-Host "Tarefa nao encontrada: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "=== 6. Conteudo de C:\Logs\DataSync (10 mais recentes) ===" -ForegroundColor Cyan
    Get-ChildItem "C:\Logs\DataSync" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 10 Name, Length, LastWriteTime |
        Format-Table -AutoSize

    Write-Host ""
    Write-Host "=== 7. Modulo SqlServer disponivel? ===" -ForegroundColor Cyan
    $modulo = Get-Module -ListAvailable SqlServer | Select-Object -First 1
    if ($modulo) {
        Write-Host "SqlServer versao $($modulo.Version)" -ForegroundColor Green
    } else {
        Write-Host "Modulo SqlServer NAO INSTALADO neste servidor" -ForegroundColor Red
    }
}

Remove-PSSession $session
Write-Host ""
Write-Host "Diagnostico concluido." -ForegroundColor Cyan
pause
