# Monitorar Data Sync - Tempo Real
# Roda continuamente e alerta sobre falhas

$LogPath = "C:\Logs\DataSync"
$AlertasPath = "$LogPath\alertas_$(Get-Date -Format 'yyyy-MM-dd').log"
$UltimaLeitura = @{}

function Log-Alerta {
    param(
        [string]$Mensagem,
        [string]$Nivel = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Entrada = "[$Timestamp] [$Nivel] $Mensagem"
    Add-Content -Path $AlertasPath -Value $Entrada -Encoding UTF8
    Write-Host $Entrada -ForegroundColor $(if($Nivel -eq "CRÍTICO") {"Red"} else {"Yellow"})
}

function Verificar-Falhas {
    $LogAtual = "$LogPath\sync_$(Get-Date -Format 'yyyy-MM-dd').log"

    if (!(Test-Path $LogAtual)) {
        return
    }

    $Conteudo = Get-Content $LogAtual -Encoding UTF8
    $Linhas = $Conteudo | Select-String "\[ERROR\]|\[ERRO\]" -AllMatches

    foreach ($Linha in $Linhas) {
        $Texto = $Linha.Line

        # Extrair informações
        if ($Texto -match "Loja (\d+).*-\s+(.+)") {
            $Loja = $matches[1]
            $Erro = $matches[2]
            $Horario = if ($Texto -match "\[(\d{2}:\d{2}:\d{2})\]") { $matches[1] } else { "??:??:??" }
            $Fase = if ($Texto -match "(RECEBE|ENVIA)") { $matches[1] } else { "DESCONHECIDA" }
        } else {
            continue
        }

        # Verificar se é erro novo
        if (-not $UltimaLeitura.ContainsKey("$Loja-$Erro")) {
            $UltimaLeitura["$Loja-$Erro"] = $true

            # Contar falhas da loja hoje
            $FalhasLoja = ($Conteudo | Select-String "Loja $Loja" | Select-String "\[ERROR\]").Count

            # Determinar nível de alerta
            if ($FalhasLoja -eq 1) {
                Log-Alerta "⚠️ FALHA DETECTADA - Loja: $Loja | Fase: $Fase | Erro: $Erro | Horário: $Horario" "AVISO"
                Log-Alerta "   Ação: Monitorar loja $Loja" "AVISO"
            } elseif ($FalhasLoja -eq 2) {
                Log-Alerta "🔴 ALERTA CRÍTICO - Loja $Loja falhou 2x hoje! | Fase: $Fase | Erro: $Erro" "CRÍTICO"
                Log-Alerta "   Ação: Investigar atalho ou conexão da Loja $Loja AGORA" "CRÍTICO"
            } else {
                Log-Alerta "🔴🔴 CRÍTICO - Loja $Loja falhou $FalhasLoja vezes! | Erro: $Erro" "CRÍTICO"
                Log-Alerta "   Ação: AÇÃO IMEDIATA NECESSÁRIA - Investigar Loja $Loja no servidor" "CRÍTICO"
            }
        }
    }
}

# Criar arquivo de alertas se não existir
if (!(Test-Path $AlertasPath)) {
    "Monitoramento iniciado: $(Get-Date)" | Out-File $AlertasPath -Encoding UTF8
}

Write-Host "========================================" -ForegroundColor Green
Write-Host "Monitorador Data Sync - TEMPO REAL" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Monitorando: $LogPath" -ForegroundColor Cyan
Write-Host "Alertas: $AlertasPath" -ForegroundColor Cyan
Write-Host "Pressione CTRL+C para parar" -ForegroundColor Yellow
Write-Host ""

# Loop infinito - verificar a cada 10 segundos
while ($true) {
    try {
        Verificar-Falhas
        Start-Sleep -Seconds 10
    }
    catch {
        Log-Alerta "Erro ao verificar logs: $_" "ERRO"
        Start-Sleep -Seconds 10
    }
}
