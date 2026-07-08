# Data Sync - Automacao 38 Lojas
# Recebe_XX -> Envia_XX para cada loja
# Horarios: 10:30, 14:30, 16:30
# EXECUTA NO SERVIDOR 192.168.0.147

# Configuracoes
$ServidorPath = "C:\Users\Datasync\Desktop\DATA SYNC SERVER"
$LogPath = "C:\Logs\DataSync"
$LogFile = "$LogPath\sync_$(Get-Date -Format 'yyyy-MM-dd').log"

# Configuracoes de Email
$EmailRemetente = "daniella@dorinhos.com.br"
$EmailDestino = "daniella@dorinhos.com.br"
$SmtpServer = "smtp.office365.com"
$SmtpPort = 587
$ArquivoCredencial = "C:\Users\Daniella\ti\.email_cred"

# Array com as 38 lojas que precisam sincronizar
$Lojas = @(3, 4, 5, 6, 7, 9, 14, 16, 17, 21, 23, 26, 28, 29, 31, 32, 33, 34, 36, 37, 38, 40, 41, 42, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57)

# Criar pasta de logs se nao existir
if (!(Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
}

# Funcao: Registrar log
function Log-Message {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8
    Write-Host $LogEntry
}

# Funcao: Notificacao desktop
function Notify-Desktop {
    param(
        [string]$Titulo,
        [string]$Mensagem
    )
    $SessionID = Get-Process -Name explorer -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SessionId -First 1
    if ($SessionID) {
        msg.exe $SessionID "/TIME:30" "/W" "$Titulo`n$Mensagem" 2>$null
    }
}

# Funcao: Enviar email com alerta de erro
function Send-ErrorEmail {
    param(
        [string]$Remetente,
        [string]$Destinatario,
        [string]$SmtpServer,
        [int]$SmtpPort,
        [string]$ArquivoCred,
        [string]$LojasFalhadas,
        [int]$TotalFalhas,
        [int]$TotalSucesso
    )

    try {
        # Verificar se arquivo de credenciais existe
        if (!(Test-Path $ArquivoCred)) {
            Log-Message "[ERRO] Arquivo de credenciais não encontrado: $ArquivoCred" "ERROR"
            Log-Message "[DICA] Execute primeiro: powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\Daniella\ti\guardar-senha-email.ps1'" "INFO"
            return
        }

        # Descriptografar a senha
        $senhaSegura = Get-Content $ArquivoCred | ConvertTo-SecureString
        $credencial = New-Object System.Management.Automation.PSCredential($Remetente, $senhaSegura)

        $assunto = "[ALERTA] Data Sync - Falha em $TotalFalhas loja(s)"
        $corpo = @"
ALERTA DE ERRO - DATA SYNC

Data/Hora: $(Get-Date -Format "dd/MM/yyyy HH:mm:ss")

RESUMO:
- Lojas com SUCESSO: $TotalSucesso
- Lojas com FALHA: $TotalFalhas

LOJAS COM ERRO:
$LojasFalhadas

Verifique o log em: C:\Logs\DataSync\sync_$(Get-Date -Format 'yyyy-MM-dd').log

---
Mensagem automática - Data Sync Automação
"@

        $params = @{
            SmtpServer = $SmtpServer
            Port = $SmtpPort
            UseSsl = $true
            Credential = $credencial
            From = $Remetente
            To = $Destinatario
            Subject = $assunto
            Body = $corpo
        }

        Send-MailMessage @params
        Log-Message "[EMAIL] Alerta enviado para $Destinatario" "INFO"
    }
    catch {
        Log-Message "[ERRO] Falha ao enviar email: $_" "ERROR"
    }
}

# Funcao: Executar atalho e verificar resultado no log do Linx DataSync
function Execute-Atalho {
    param(
        [string]$AtalhoPath,
        [string]$Loja,
        [string]$Tipo,
        [string]$VBSScript,
        [int]$TimeoutSeconds = 60
    )

    $logLinx = "C:\Program Files (x86)\Linx Sistemas\Linx Datasync (Retail)\Log"
    $hoje    = Get-Date -Format "yyyyMMdd"

    try {
        Log-Message "Executando: Loja $Loja - $Tipo..."

        if ([string]::IsNullOrWhiteSpace($AtalhoPath)) {
            Log-Message "[ERRO] Caminho do atalho vazio para Loja $Loja - $Tipo" "ERROR"
            return $false
        }

        if (!(Test-Path $AtalhoPath)) {
            Log-Message "[ERRO] Atalho nao encontrado: $AtalhoPath" "ERROR"
            return $false
        }

        $WshShell      = New-Object -ComObject WScript.Shell
        $atalho        = $WshShell.CreateShortcut($AtalhoPath)
        $TargetProgram = $atalho.TargetPath
        $TargetArgs    = $atalho.Arguments
        $WorkingDir    = $atalho.WorkingDirectory

        if ([string]::IsNullOrWhiteSpace($TargetProgram)) {
            Log-Message "[ERRO] Atalho sem programa destino: $AtalhoPath" "ERROR"
            return $false
        }

        $antesExecucao = Get-Date

        # Iniciar e aguardar conclusao real (nao apenas 5 segundos)
        $processo  = Start-Process -FilePath $TargetProgram -ArgumentList $TargetArgs -WorkingDirectory $WorkingDir -NoNewWindow -PassThru -ErrorAction Stop
        $terminou  = $processo.WaitForExit($TimeoutSeconds * 1000)

        if (-not $terminou) {
            $processo.Kill() | Out-Null
            Log-Message "[ERRO] Loja $Loja - ${Tipo}: TIMEOUT apos $([int]($TimeoutSeconds/60)) minutos" "ERROR"
            return $false
        }

        # Aguardar log ser gravado em disco
        Start-Sleep -Seconds 3

        # Localizar log do Linx DataSync gerado nesta execucao
        $logFile = Get-ChildItem $logLinx -ErrorAction SilentlyContinue |
                   Where-Object {
                       $_.Name -like "*$hoje*" -and
                       $_.Name -like "*LOJA $Loja *" -and
                       $_.LastWriteTime -gt $antesExecucao
                   } |
                   Sort-Object LastWriteTime -Descending |
                   Select-Object -First 1

        if (-not $logFile) {
            Log-Message "[ERRO] Loja $Loja - ${Tipo}: Log do Linx nao gerado (falha de conexao ou configuracao)" "ERROR"
            return $false
        }

        # Log vazio = conectou mas nao transferiu nada (falha de conexao com a loja)
        if ($logFile.Length -eq 0) {
            Log-Message "[ERRO] Loja $Loja - ${Tipo}: Falha de conexao com a loja (log vazio)" "ERROR"
            return $false
        }

        # Verificar se a ultima linha confirma sucesso
        $ultimaLinha = Get-Content $logFile.FullName -Encoding Default -Tail 1 -ErrorAction SilentlyContinue
        if ($ultimaLinha -notlike "*transferencia foi concluida com sucesso*" -and
            $ultimaLinha -notlike "*transfer*ncia foi conclu*da com sucesso*") {
            Log-Message "[ERRO] Loja $Loja - ${Tipo}: Transferencia nao concluida. Ultimo registro: $ultimaLinha" "ERROR"
            return $false
        }

        Log-Message "[OK] Loja $Loja - $Tipo concluido com sucesso" "SUCCESS"
        return $true
    }
    catch {
        Log-Message "[ERRO] Loja $Loja - $Tipo - $_" "ERROR"
        return $false
    }
}

# Helper: aguarda jobs, grava logs no arquivo e retorna {loja -> bool}
function Collect-Jobs {
    param([hashtable]$Jobs, [string]$LogFilePath)
    $resultados = @{}
    foreach ($Loja in ($Jobs.Keys | Sort-Object)) {
        $res = Receive-Job $Jobs[$Loja]
        Remove-Job $Jobs[$Loja]
        foreach ($entry in $res.Logs) {
            Add-Content -Path $LogFilePath -Value $entry -Encoding UTF8
            Write-Host $entry
        }
        $resultados[$Loja] = $res.Sucesso
    }
    return $resultados
}

# MAIN: Sincronizar todas as 38 lojas em paralelo
function Main {
    $diaSemana = (Get-Date).DayOfWeek
    if ($diaSemana -eq "Saturday" -or $diaSemana -eq "Sunday") {
        Log-Message "EXECUCAO BLOQUEADA - FIM DE SEMANA" "WARNING"
        Log-Message "Dia: $diaSemana - Sincronizacao nao ocorre em sabados e domingos" "INFO"
        return
    }

    Log-Message "========================================" "INFO"
    Log-Message "SINCRONIZANDO 39 LOJAS" "INFO"
    Log-Message "Horario: $(Get-Date -Format 'HH:mm:ss')" "INFO"
    Log-Message "========================================" "INFO"

    $DataInicio          = Get-Date
    $LojasSucesso        = 0
    $LojasFalha          = 0
    $LojasFalhadasList   = @()
    $LojasFalhadasRecebe = @()

    $CaminhoReceber = Join-Path $ServidorPath "RECEBER"
    $CaminhoEnviar  = Join-Path $ServidorPath "ENVIAR"
    $logLinxPath    = "C:\Program Files (x86)\Linx Sistemas\Linx Datasync (Retail)\Log"
    $statusDir      = "$LogPath\status"

    # Criar/limpar pasta de status para o novo ciclo
    if (!(Test-Path $statusDir)) { New-Item -ItemType Directory $statusDir -Force | Out-Null }
    Remove-Item "$statusDir\*.txt" -Force -ErrorAction SilentlyContinue

    # Script block executado em paralelo para cada loja
    # Escreve arquivo de status em tempo real para o painel
    $jobBlock = {
        param($AtalhoPath, $Loja, $Tipo, $logLinxPath, $TimeoutMs, $statusDir)
        $logs    = [System.Collections.Generic.List[string]]::new()
        $sucesso = $false

        function alog { param($m, $l="INFO") $logs.Add("[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$l] $m") }

        alog "Loja ${Loja}: Executando ${Tipo}..."
        alog "Executando: Loja $Loja - ${Tipo}..."

        # Status: iniciando
        try { Set-Content "$statusDir\loja_$Loja.txt" "$Tipo|RODANDO|$(Get-Date -Format 'HH:mm:ss')" -Encoding UTF8 } catch {}

        try {
            $ws    = New-Object -ComObject WScript.Shell
            $lnk   = $ws.CreateShortcut($AtalhoPath)
            $prog  = $lnk.TargetPath
            $largs = $lnk.Arguments
            $wdir  = $lnk.WorkingDirectory

            if ([string]::IsNullOrWhiteSpace($prog)) {
                alog "[ERRO] Loja $Loja - ${Tipo}: Atalho sem programa destino" "ERROR"
            } else {
                $hojeStr    = Get-Date -Format "yyyyMMdd"
                # Lojas numericas: log tem "LOJA XX"; E-COMMERCE: log nao tem prefixo "LOJA"
                $lojaFiltro = if ($Loja -match '^\d') { "*LOJA $Loja*" } else { "*$Loja*" }

                # Pre-verificacao apenas para RECEBE: se o log de hoje ja tem sucesso, pula
                # (lojas 31/03 demoram 4h no Linx — o log fica pronto antes do ciclo seguinte)
                # ENVIA nunca pula: pedidos novos chegam entre ciclos e precisam ser enviados
                if ($Tipo -eq "RECEBE") {
                    $logPreCheck = Get-ChildItem $logLinxPath -ErrorAction SilentlyContinue |
                                   Where-Object { $_.Name -like "*$hojeStr*" -and $_.Name -like $lojaFiltro } |
                                   Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if ($logPreCheck -and $logPreCheck.Length -gt 0) {
                        $ultimaPreCheck = Get-Content $logPreCheck.FullName -Encoding Default -Tail 1 -ErrorAction SilentlyContinue
                        if ($ultimaPreCheck -like "*transferencia foi concluida com sucesso*" -or
                            $ultimaPreCheck -like "*transfer*ncia foi conclu*da com sucesso*") {
                            alog "[OK] Loja $Loja - ${Tipo} ja concluido hoje (sync anterior)" "SUCCESS"
                            $sucesso = $true
                        }
                    }
                }

                if (-not $sucesso) {
                    $antes    = Get-Date
                    $proc     = Start-Process -FilePath $prog -ArgumentList $largs -WorkingDirectory $wdir -NoNewWindow -PassThru -ErrorAction Stop
                    $terminou = $proc.WaitForExit($TimeoutMs)

                    if (-not $terminou) {
                        try { $proc.Kill() } catch {}
                        alog "[ERRO] Loja $Loja - ${Tipo}: TIMEOUT apos $([int]($TimeoutMs/60000)) minutos" "ERROR"
                    } else {
                        Start-Sleep -Seconds 3
                        $hoje    = Get-Date -Format "yyyyMMdd"
                        $logFile = Get-ChildItem $logLinxPath -ErrorAction SilentlyContinue |
                                   Where-Object { $_.Name -like "*$hoje*" -and $_.Name -like $lojaFiltro -and $_.LastWriteTime -gt $antes } |
                                   Sort-Object LastWriteTime -Descending | Select-Object -First 1

                        if (-not $logFile) {
                            alog "[ERRO] Loja $Loja - ${Tipo}: Log do Linx nao gerado" "ERROR"
                        } elseif ($logFile.Length -eq 0) {
                            alog "[ERRO] Loja $Loja - ${Tipo}: Falha de conexao (log vazio)" "ERROR"
                        } else {
                            $ultima = Get-Content $logFile.FullName -Encoding Default -Tail 1 -ErrorAction SilentlyContinue
                            if ($ultima -notlike "*transferencia foi concluida com sucesso*" -and
                                $ultima -notlike "*transfer*ncia foi conclu*da com sucesso*") {
                                alog "[ERRO] Loja $Loja - ${Tipo}: Transferencia nao concluida. Ultimo: $ultima" "ERROR"
                            } else {
                                alog "[OK] Loja $Loja - ${Tipo} concluido com sucesso" "SUCCESS"
                                $sucesso = $true
                            }
                        }
                    }
                }
            }
        }
        catch {
            alog "[ERRO] Loja $Loja - ${Tipo}: $_" "ERROR"
        }

        # Status: resultado final
        $statusFinal = if ($sucesso) { "OK" } else { "ERRO" }
        try { Set-Content "$statusDir\loja_$Loja.txt" "$Tipo|$statusFinal|$(Get-Date -Format 'HH:mm:ss')" -Encoding UTF8 } catch {}

        return @{ Loja=$Loja; Sucesso=$sucesso; Logs=$logs.ToArray() }
    }

    # Tamanho do lote — quantas lojas rodam ao mesmo tempo
    $loteTamanho = 10

    # Helper: executa uma fase (RECEBE ou ENVIA) em lotes de $loteTamanho
    function Executar-EmLotes {
        param(
            [int[]]$NumerosLoja,
            [string]$Tipo,
            [string]$CaminhoPasta,
            [string]$FiltroAtalho,
            [int]$TimeoutMs
        )
        $falhas = @()
        $total  = $NumerosLoja.Count
        $loteNum = 0

        for ($i = 0; $i -lt $total; $i += $loteTamanho) {
            $loteNum++
            $lote = $NumerosLoja[$i..([Math]::Min($i + $loteTamanho - 1, $total - 1))]
            Log-Message "Lote ${loteNum}: $Tipo lojas $($lote | ForEach-Object { '{0:D2}' -f $_ }) ..." "INFO"

            $jobs = @{}
            foreach ($NumeroLoja in $lote) {
                $Loja   = "{0:D2}" -f $NumeroLoja
                $atalho = Get-ChildItem -Path $CaminhoPasta -Filter ($FiltroAtalho -replace 'XX', $Loja) -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($null -eq $atalho) {
                    Log-Message "[ERRO] Atalho $Tipo nao encontrado para Loja $Loja" "ERROR"
                    $falhas += $Loja
                    continue
                }
                $jobs[$Loja] = Start-Job -ScriptBlock $jobBlock -ArgumentList $atalho.FullName, $Loja, $Tipo, $logLinxPath, $TimeoutMs, $statusDir
            }

            if ($jobs.Count -gt 0) {
                $jobs.Values | Wait-Job | Out-Null
                $resultados = Collect-Jobs -Jobs $jobs -LogFilePath $LogFile
                foreach ($loja in ($resultados.Keys | Sort-Object)) {
                    if (!$resultados[$loja]) { $falhas += $loja }
                }
            }
        }
        return $falhas
    }

    # FASE 1: RECEBE em lotes
    Log-Message "FASE 1: RECEBE das 39 lojas (lotes de $loteTamanho)..." "INFO"

    if (!(Test-Path $CaminhoReceber)) {
        Log-Message "[ERRO] Caminho RECEBER nao acessivel: $CaminhoReceber" "ERROR"
        return
    }

    $LojasFalhadasRecebe = @(Executar-EmLotes -NumerosLoja $Lojas -Tipo "RECEBE" -CaminhoPasta $CaminhoReceber -FiltroAtalho "RECEBE LOJA XX*" -TimeoutMs 240000)

    # E-COMMERCE RECEBE
    $atalhoEcomRecebe = Get-ChildItem -Path $CaminhoReceber -Filter "RECEBE LOJA E-COMMERCE*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($atalhoEcomRecebe) {
        $jobEcom = @{ "E-COMMERCE" = (Start-Job -ScriptBlock $jobBlock -ArgumentList $atalhoEcomRecebe.FullName, "E-COMMERCE", "RECEBE", $logLinxPath, 240000, $statusDir) }
        $jobEcom.Values | Wait-Job | Out-Null
        $resEcom = Collect-Jobs -Jobs $jobEcom -LogFilePath $LogFile
        if (!$resEcom["E-COMMERCE"]) { $LojasFalhadasRecebe += "E-COMMERCE" }
    } else {
        Log-Message "[ERRO] Atalho RECEBE LOJA E-COMMERCE nao encontrado" "ERROR"
        $LojasFalhadasRecebe += "E-COMMERCE"
    }

    $totalRecebeOk = ($Lojas.Count + 1) - $LojasFalhadasRecebe.Count
    Log-Message "RECEBE concluido: $totalRecebeOk lojas OK, $($LojasFalhadasRecebe.Count) falha(s)" "INFO"

    # Pausa 15 minutos
    Log-Message "" "INFO"
    Log-Message "Aguardando 15 minutos antes de iniciar ENVIA..." "INFO"
    Start-Sleep -Seconds 900

    # FASE 2: ENVIA em lotes (so lojas com RECEBE ok)
    Log-Message "" "INFO"
    Log-Message "FASE 2: ENVIA das lojas com RECEBE ok (lotes de $loteTamanho)..." "INFO"

    if (!(Test-Path $CaminhoEnviar)) {
        Log-Message "[ERRO] Caminho ENVIAR nao acessivel: $CaminhoEnviar" "ERROR"
        foreach ($NumeroLoja in $Lojas) {
            $Loja = "{0:D2}" -f $NumeroLoja
            if ($LojasFalhadasRecebe -notcontains $Loja) { $LojasFalha++; $LojasFalhadasList += $Loja }
        }
    } else {
        # Marcar IGNORADO as lojas que falharam no RECEBE
        foreach ($NumeroLoja in $Lojas) {
            $Loja = "{0:D2}" -f $NumeroLoja
            if ($LojasFalhadasRecebe -contains $Loja) {
                Log-Message "Loja ${Loja}: ENVIA ignorado (RECEBE falhou)" "WARNING"
                try { Set-Content "$statusDir\loja_$Loja.txt" "ENVIA|IGNORADO|$(Get-Date -Format 'HH:mm:ss')" -Encoding UTF8 } catch {}
                $LojasFalha++
                $LojasFalhadasList += $Loja
            }
        }

        # Lojas que precisam de mais tempo no ENVIA (~13 min)
        $lojasLentasEnvia = @(3, 38, 47, 48, 52, 53)

        # Executar ENVIA apenas nas lojas com RECEBE ok
        $lojasParaEnviar = $Lojas | Where-Object { $LojasFalhadasRecebe -notcontains ("{0:D2}" -f $_) }
        if ($lojasParaEnviar.Count -gt 0) {
            # Separar lojas lentas das rapidas
            $lojasLentasOk   = @($lojasParaEnviar | Where-Object { $lojasLentasEnvia -contains $_ })
            $lojasRapidasOk  = @($lojasParaEnviar | Where-Object { $lojasLentasEnvia -notcontains $_ })

            $falhasEnvia = @()

            # Lote prioritario: lojas lentas com timeout de 15 min
            if ($lojasLentasOk.Count -gt 0) {
                $lentasStr = $lojasLentasOk -join ', '
                Log-Message "ENVIA prioritario: lojas lentas ($lentasStr) - timeout 15 min" "INFO"
                $falhasEnvia += @(Executar-EmLotes -NumerosLoja $lojasLentasOk -Tipo "ENVIA" -CaminhoPasta $CaminhoEnviar -FiltroAtalho "ENVIA LOJA XX*" -TimeoutMs 900000)
            }

            # Lojas rapidas com timeout de 8 min
            if ($lojasRapidasOk.Count -gt 0) {
                $falhasEnvia += @(Executar-EmLotes -NumerosLoja $lojasRapidasOk -Tipo "ENVIA" -CaminhoPasta $CaminhoEnviar -FiltroAtalho "ENVIA LOJA XX*" -TimeoutMs 480000)
            }

            foreach ($loja in $lojasParaEnviar) {
                $Loja = "{0:D2}" -f $loja
                if ($falhasEnvia -contains $Loja) { $LojasFalha++; $LojasFalhadasList += $Loja }
                else { $LojasSucesso++ }
            }
        }

        # E-COMMERCE ENVIA
        if ($LojasFalhadasRecebe -contains "E-COMMERCE") {
            Log-Message "Loja E-COMMERCE: ENVIA ignorado (RECEBE falhou)" "WARNING"
            try { Set-Content "$statusDir\loja_E-COMMERCE.txt" "ENVIA|IGNORADO|$(Get-Date -Format 'HH:mm:ss')" -Encoding UTF8 } catch {}
            $LojasFalha++
            $LojasFalhadasList += "E-COMMERCE"
        } else {
            $atalhoEcomEnvia = Get-ChildItem -Path $CaminhoEnviar -Filter "ENVIA LOJA E-COMMERCE*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($atalhoEcomEnvia) {
                $jobEcomE = @{ "E-COMMERCE" = (Start-Job -ScriptBlock $jobBlock -ArgumentList $atalhoEcomEnvia.FullName, "E-COMMERCE", "ENVIA", $logLinxPath, 480000, $statusDir) }
                $jobEcomE.Values | Wait-Job | Out-Null
                $resEcomE = Collect-Jobs -Jobs $jobEcomE -LogFilePath $LogFile
                if (!$resEcomE["E-COMMERCE"]) { $LojasFalha++; $LojasFalhadasList += "E-COMMERCE" }
                else { $LojasSucesso++ }
            } else {
                Log-Message "[ERRO] Atalho ENVIA LOJA E-COMMERCE nao encontrado" "ERROR"
                $LojasFalha++; $LojasFalhadasList += "E-COMMERCE"
            }
        }
    }

    # Resumo final
    $DataFim = Get-Date
    $Duracao = ($DataFim - $DataInicio).TotalMinutes
    Log-Message "" "INFO"
    Log-Message "========================================" "INFO"
    Log-Message "RESUMO DA SINCRONIZACAO" "INFO"
    Log-Message "========================================" "INFO"
    Log-Message "[OK] Lojas com sucesso: $LojasSucesso" "INFO"
    Log-Message "[ERRO] Lojas com falha: $LojasFalha" "INFO"
    Log-Message "[TEMPO] Total: $([Math]::Round($Duracao, 2)) minutos" "INFO"

    if ($LojasFalha -gt 0) {
        $LojasFalhadasStr = ($LojasFalhadasList -join ", ")
        Log-Message "[AVISO] Lojas com FALHA: $LojasFalhadasStr" "WARNING"
        Notify-Desktop "Data Sync - Erro em Lojas" "Falha em: $LojasFalhadasStr"
    } else {
        Log-Message "[SUCESSO] TODAS AS LOJAS SINCRONIZADAS COM SUCESSO!" "SUCCESS"
    }
}

# Executar
Main
