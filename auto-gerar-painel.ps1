# Regenerar painel AUTOMATICAMENTE quando log eh atualizado
# Verifica a cada 30 segundos se o log mudou

$ultimaVerificacao = $null
$intervaloVerificacao = 30  # segundos

while($true) {
    $hoje = Get-Date -Format 'yyyy-MM-dd'
    $logFile = "C:\Logs\DataSync\sync_$hoje.log"
    $paineFile = "C:\Logs\DataSync\painel.html"

    # Verificar se log mudou
    if(Test-Path $logFile) {
        $ultimaMod = (Get-Item $logFile).LastWriteTime

        # Se log foi modificado desde ultima verificacao
        if($ultimaVerificacao -eq $null -or $ultimaMod -gt $ultimaVerificacao) {
            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Log atualizado! Regenerando painel..." -ForegroundColor Cyan

            # Executar gerador de painel
            & "C:\Users\Daniella\ti\gerar-painel-datasync.ps1" 2>$null

            Write-Host "$(Get-Date -Format 'HH:mm:ss') - Painel regenerado com cores e hora ATUALIZADAS!" -ForegroundColor Green

            $ultimaVerificacao = $ultimaMod
        }
    }

    Start-Sleep -Seconds $intervaloVerificacao
}
