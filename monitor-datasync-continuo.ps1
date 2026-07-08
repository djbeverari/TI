# Monitor Data Sync - CONTINUO 24/7 (REDE)
# Monitora alertas EM TEMPO REAL de QUALQUER MAQUINA DA REDE
# Acessa logs via UNC path do servidor 192.168.0.147

# Configuracoes
$ServidorIP = "192.168.0.147"
$alertFile = "\\$ServidorIP\Logs\DataSync\alertas_$(Get-Date -Format 'yyyy-MM-dd').log"
$lojasFalhadas = @{}  # Rastrear falhas por loja
$ultimaLinha = 0
$checkInterval = 10   # Check a cada 10 segundos

Write-Host "════════════════════════════════════════════════"
Write-Host "MONITOR DATA SYNC - CONTINUO 24/7"
Write-Host "════════════════════════════════════════════════"
Write-Host "Modo REDE: Acessando servidor $ServidorIP"
Write-Host "Arquivo monitorado: $alertFile"
Write-Host "Intervalo de check: $checkInterval segundos"
Write-Host "Iniciado em: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"
Write-Host ""
Write-Host "Monitorando... (pressione CTRL+C para parar)"
Write-Host ""

# Função para extrair informações de alerta
function Parse-Alerta {
    param($novasLinhas)

    $i = 0
    while($i -lt $novasLinhas.Count) {
        $linha = $novasLinhas[$i]

        # Procurar por padrao de falha
        if($linha -match 'FALHA EM TEMPO REAL') {
            $loja = ""
            $erro = ""
            $horario = ""
            $acao = ""

            # Procurar proximas linhas para extrair informacoes
            if($i + 1 -lt $novasLinhas.Count -and $novasLinhas[$i + 1] -match 'Loja: (\d+)') {
                $loja = $matches[1]
            }
            if($i + 2 -lt $novasLinhas.Count -and $novasLinhas[$i + 2] -match 'Erro: (.+)') {
                $erro = $matches[1]
            }
            if($i + 3 -lt $novasLinhas.Count -and $novasLinhas[$i + 3] -match 'Horario: (.+)') {
                $horario = $matches[1]
            }
            if($i + 4 -lt $novasLinhas.Count -and $novasLinhas[$i + 4] -match 'Acao: (.+)') {
                $acao = $matches[1]
            }

            if($loja) {
                # Rastrear falhas por loja
                if(-not $lojasFalhadas.ContainsKey($loja)) {
                    $lojasFalhadas[$loja] = 0
                }
                $lojasFalhadas[$loja]++

                $contagem = $lojasFalhadas[$loja]
                $nivelAlerta = ""

                if($contagem -eq 1) {
                    $nivelAlerta = "PRIMEIRA FALHA"
                } elseif($contagem -eq 2) {
                    $nivelAlerta = "SEGUNDA FALHA - CRITICO!"
                } else {
                    $nivelAlerta = "TERCEIRA+ FALHA - ACAO IMEDIATA!"
                }

                # Exibir alerta
                Write-Host ""
                Write-Host "════════════════════════════════════════════════"
                Write-Host "ALERTA EM TEMPO REAL - $(Get-Date -Format 'HH:mm:ss')"
                Write-Host "════════════════════════════════════════════════"
                Write-Host "$nivelAlerta"
                Write-Host ""
                Write-Host "Loja: $loja (Falha #$contagem hoje)"
                Write-Host "Erro: $erro"
                Write-Host "Horario: $horario"
                Write-Host "Acao: $acao"
                Write-Host ""
                Write-Host "────────────────────────────────────────────────"
                Write-Host ""

                # Notificacao desktop
                $titulo = "Data Sync - FALHA Loja $loja"
                $mensagem = "Falha #$contagem`nErro: $erro`nAcao: $acao"
                try {
                    msg.exe $env:USERNAME "/TIME:30" "/W" "$titulo`n$mensagem" 2>$null
                } catch {}
            }
        }

        $i++
    }
}

# Verificar acesso ao servidor antes de comecar
Write-Host "Verificando acesso ao servidor..."
$tentativas = 0
while($tentativas -lt 3) {
    if(Test-Path "\\$ServidorIP\Logs\DataSync" -ErrorAction SilentlyContinue) {
        Write-Host "Servidor acessivel! Iniciando monitoramento..."
        Write-Host ""
        break
    }
    $tentativas++
    if($tentativas -lt 3) {
        Write-Host "Servidor inacessivel. Tentando novamente em 5s... (tentativa $tentativas/3)"
        Start-Sleep -Seconds 5
    }
}

if($tentativas -ge 3) {
    Write-Host "Nao foi possivel acessar o servidor $ServidorIP"
    Write-Host "Verifique:"
    Write-Host "  - Servidor esta ligado?"
    Write-Host "  - Caminho compartilhado esta ativo?"
    Write-Host "  - Voce tem permissao de acesso?"
    Write-Host ""
    Write-Host "Caminho: \\$ServidorIP\Logs\DataSync"
    exit 1
}

# Loop de monitoramento contínuo
while($true) {
    try {
        if(Test-Path $alertFile -ErrorAction SilentlyContinue) {
            $linhas = @(Get-Content $alertFile 2>$null)
            $totalLinhas = $linhas.Count

            if($totalLinhas -gt $ultimaLinha) {
                $novasLinhas = $linhas[$ultimaLinha..($totalLinhas-1)]
                Parse-Alerta $novasLinhas
                $ultimaLinha = $totalLinhas
            }
        }
    } catch {
        Write-Host "Erro ao ler arquivo: $_"
    }

    Start-Sleep -Seconds $checkInterval
}
