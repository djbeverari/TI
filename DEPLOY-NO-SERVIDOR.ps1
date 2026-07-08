# DEPLOY - Atualizar painel e bats no servidor
# Execute com: botao direito > Executar com PowerShell
# OU: powershell -ExecutionPolicy Bypass -File "DEPLOY-NO-SERVIDOR.ps1"

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host " DEPLOY - Painel + Bats no servidor 192.168.0.147" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Credencial
$cred = Get-Credential -UserName "Datasync" -Message "Senha do usuario Datasync no servidor 192.168.0.147"
if (-not $cred) { Write-Host "Cancelado." -ForegroundColor Red; pause; exit 1 }

Write-Host "Conectando ao servidor..." -ForegroundColor Cyan
$session = New-PSSession -ComputerName 192.168.0.147 -Credential $cred -ErrorAction Stop

# Ler arquivos locais
$painelScript = Get-Content "$ScriptDir\gerar-painel-datasync.ps1" -Raw -Encoding UTF8
$executarBat  = Get-Content "$ScriptDir\executar-datasync.bat"      -Raw
$pausarBat    = Get-Content "$ScriptDir\pausar-agendamentos.bat"    -Raw
$retomarBat   = Get-Content "$ScriptDir\retomar-agendamentos.bat"   -Raw

Write-Host "Conectado. Enviando arquivos..." -ForegroundColor Green

Invoke-Command -Session $session -ScriptBlock {
    param($painel, $executar, $pausar, $retomar)

    $tiDir   = "C:\Users\Datasync\Desktop\ti"
    $desktop = "C:\Users\Datasync\Desktop"
    $logDir  = "C:\Logs\DataSync"
    $utf8    = [System.Text.UTF8Encoding]::new($false)
    $ansi    = [System.Text.Encoding]::Default

    # Atualizar painel
    [System.IO.File]::WriteAllText("$tiDir\gerar-painel-datasync.ps1", $painel, $utf8)
    Write-Host "[OK] gerar-painel-datasync.ps1 atualizado" -ForegroundColor Green

    # Gravar bats no Desktop
    [System.IO.File]::WriteAllText("$desktop\executar-datasync.bat",     $executar, $ansi)
    [System.IO.File]::WriteAllText("$desktop\pausar-agendamentos.bat",   $pausar,   $ansi)
    [System.IO.File]::WriteAllText("$desktop\retomar-agendamentos.bat",  $retomar,  $ansi)
    Write-Host "[OK] .bat atualizados no Desktop" -ForegroundColor Green

    # Reiniciar gerador do painel
    Stop-ScheduledTask  -TaskName "DataSyncPainel" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-ScheduledTask -TaskName "DataSyncPainel"
    Start-Sleep -Seconds 6
    Write-Host "[OK] DataSyncPainel reiniciado" -ForegroundColor Green

    # Verificar painel gerado
    if (Test-Path "$logDir\painel.html") {
        Write-Host "[OK] painel.html: $((Get-Item "$logDir\painel.html").LastWriteTime)" -ForegroundColor Green
    }

    # Verificar bats
    Write-Host ""
    Write-Host "=== Testando bats ===" -ForegroundColor Cyan

    schtasks /Change /TN "DataSync_1030" /Disable | Out-Null
    $s = (Get-ScheduledTask -TaskName "DataSync_1030").State
    Write-Host "pausar  -> DataSync_1030: $s $(if($s -eq 'Disabled'){'[OK]'} else {'[FALHOU]'})" -ForegroundColor $(if($s -eq 'Disabled'){'Green'}else{'Red'})

    schtasks /Change /TN "DataSync_1030" /Enable | Out-Null
    schtasks /Change /TN "DataSync_1430" /Enable | Out-Null
    schtasks /Change /TN "DataSync_1630" /Enable | Out-Null
    $s = (Get-ScheduledTask -TaskName "DataSync_1030").State
    Write-Host "retomar -> DataSync_1030: $s $(if($s -eq 'Ready'){'[OK]'} else {'[FALHOU]'})" -ForegroundColor $(if($s -eq 'Ready'){'Green'}else{'Red'})

    $batOk = Test-Path "$tiDir\data-sync-automacao.ps1"
    Write-Host "executar-> script em ti\: $(if($batOk){'[OK]'}else{'[NAO ENCONTRADO]'})" -ForegroundColor $(if($batOk){'Green'}else{'Red'})

    Write-Host ""
    Write-Host "=== Tarefas no servidor ===" -ForegroundColor Cyan
    Get-ScheduledTask | Where-Object {$_.TaskName -like "DataSync*"} |
        Select-Object TaskName, State | Format-Table -AutoSize

} -ArgumentList $painelScript, $executarBat, $pausarBat, $retomarBat

Remove-PSSession $session

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host " DEPLOY CONCLUIDO!" -ForegroundColor Green
Write-Host " Painel: http://192.168.0.147:8080/painel.html" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
pause
