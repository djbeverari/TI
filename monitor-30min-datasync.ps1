# Monitor Data Sync - PRIMEIROS 30 MINUTOS apos execucao
# Verifica erros apenas durante 30 min apos cada agendamento (10:30, 14:30, 16:30)

$horariosAgendados = @("10:30", "14:30", "16:30")
$duracaoMonitoramento = 30  # minutos

while($true) {
    $horaAtual = Get-Date -Format "HH:mm"
    $minutoAtual = [int](Get-Date -Format "mm")

    # Verificar se eh horario de agendamento
    foreach($horario in $horariosAgendados) {
        $horParts = $horario -split ":"
        $horInt = [int]$horParts[0]
        $minInt = [int]$horParts[1]

        $horaAtualInt = [int](Get-Date -Format "HH")

        # Se eh 10:30, 14:30 ou 16:30 (primeiros 30 minutos)
        if($horaAtualInt -eq $horInt -and $minutoAtual -lt $duracaoMonitoramento) {

            $hoje = Get-Date -Format 'yyyy-MM-dd'
            $logFile = "C:\Logs\DataSync\sync_$hoje.log"
            $alertFile = "C:\Logs\DataSync\alertas_$hoje.log"

            # Se log existe, verificar erros
            if(Test-Path $logFile) {
                $conteudo = Get-Content $logFile -Raw
                $erros = @($conteudo | Select-String -Pattern '\[ERROR\]|\[ERRO\]|Erro:|FALHA|falha' -AllMatches)

                if($erros.Count -gt 0) {
                    # ALERTA CRITICO
                    Write-Host ""
                    Write-Host "════════════════════════════════════════════════" -ForegroundColor Red
                    Write-Host "⚠️  ALERTA CRITICO - FALHA DETECTADA!" -ForegroundColor Red
                    Write-Host "════════════════════════════════════════════════" -ForegroundColor Red
                    Write-Host ""
                    Write-Host "Horario: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Red
                    Write-Host "Erros encontrados: $($erros.Count)" -ForegroundColor Red
                    Write-Host ""

                    $erros | ForEach-Object {
                        Write-Host "  >>> $($_.Line)" -ForegroundColor Red
                    }

                    Write-Host ""
                    Write-Host "ACAO REQUERIDA:" -ForegroundColor Red
                    Write-Host "  1. Investigar erro na loja afetada"
                    Write-Host "  2. Checar conexao de rede"
                    Write-Host "  3. Verificar status do servidor"
                    Write-Host ""

                    # Salvar alerta
                    $alerta = @"
ALERTA CRITICO - $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')
Erros: $($erros.Count)
$($erros | ForEach-Object { $_.Line })
"@
                    Add-Content -Path $alertFile -Value $alerta

                    # Notificacao desktop
                    try {
                        msg.exe $env:USERNAME "/TIME:60" "/W" "DATA SYNC CRITICO`nFalha detectada nos primeiros 30 minutos`nVerifique o painel ou logs" 2>$null
                    } catch {}
                }
            }
        }
    }

    # Verificar a cada 10 segundos
    Start-Sleep -Seconds 10
}
