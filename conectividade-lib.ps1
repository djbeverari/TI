function Get-RouterIp {
    param([Parameter(Mandatory)] [string]$MachineIp)

    $partes = $MachineIp -split '\.'
    if ($partes.Count -ne 4) {
        throw "IP inválido: $MachineIp"
    }
    return "{0}.{1}.{2}.10" -f $partes[0], $partes[1], $partes[2]
}

function Get-LojaIp {
    param([Parameter(Mandatory)] [string]$Servidor)
    return ($Servidor -split '\\')[0]
}

function Get-LojaRotulo {
    param([Parameter(Mandatory)] [hashtable]$Loja)
    if ($Loja.ContainsKey('RotuloLog') -and $Loja.RotuloLog) {
        return $Loja.RotuloLog
    }
    return [string]$Loja.Numero
}

# --- Composição de alvos ---

function Get-LojasParaTeste {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Lojas,
        [string[]]$SemRoteador = @('E-COMMERCE')
    )

    $alvos = @()
    foreach ($loja in $Lojas) {
        $rotulo = Get-LojaRotulo -Loja $loja
        $ip = Get-LojaIp -Servidor $loja.Servidor

        if ($rotulo -notin $SemRoteador) {
            $alvos += [PSCustomObject]@{
                Loja = $rotulo
                Tipo = 'Roteador'
                Ip   = Get-RouterIp -MachineIp $ip
            }
        }
        $alvos += [PSCustomObject]@{
            Loja = $rotulo
            Tipo = 'Maquina'
            Ip   = $ip
        }
    }
    return $alvos
}

# --- Verificação de conectividade ---

function Test-IpsParalelo {
    param(
        [string[]]$Ips = @(),
        [int]$TimeoutMs = 2000
    )

    $resultados = @{}
    if ($Ips.Count -eq 0) {
        return $resultados
    }

    $pings = @{}
    $tarefas = @{}
    foreach ($ip in $Ips) {
        $ping = [System.Net.NetworkInformation.Ping]::new()
        $pings[$ip] = $ping
        $tarefas[$ip] = $ping.SendPingAsync($ip, $TimeoutMs)
    }

    try {
        [System.Threading.Tasks.Task]::WaitAll(@($tarefas.Values)) | Out-Null
    } catch [System.AggregateException] {
        # Uma tarefa com falha (ex.: IP malformado) faz WaitAll relançar; os resultados
        # individuais ainda são lidos abaixo via .IsFaulted, então a falha de um IP não
        # derruba o ciclo inteiro.
    }

    foreach ($ip in $Ips) {
        $tarefa = $tarefas[$ip]
        if ($tarefa.IsFaulted) {
            $resultados[$ip] = [PSCustomObject]@{
                Respondeu  = $false
                LatenciaMs = $null
            }
        } else {
            $reply = $tarefa.Result
            $sucesso = $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success
            $resultados[$ip] = [PSCustomObject]@{
                Respondeu  = $sucesso
                LatenciaMs = if ($sucesso) { $reply.RoundtripTime } else { $null }
            }
        }
        $pings[$ip].Dispose()
    }
    return $resultados
}

# --- Orquestração do ciclo ---

function Invoke-CicloConectividade {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Lojas,
        [string[]]$SemRoteador = @('E-COMMERCE'),
        [int]$TimeoutMs = 2000
    )

    $alvos = Get-LojasParaTeste -Lojas $Lojas -SemRoteador $SemRoteador
    $timestamp = (Get-Date).ToString('o')
    $linhas = @()

    $roteadorAlvos = @($alvos | Where-Object { $_.Tipo -eq 'Roteador' })
    $ipsRoteador = @($roteadorAlvos | ForEach-Object { $_.Ip })
    $resultadosRoteador = Test-IpsParalelo -Ips $ipsRoteador -TimeoutMs $TimeoutMs

    $lojasRoteadorOk = @{}
    foreach ($alvo in $roteadorAlvos) {
        $r = $resultadosRoteador[$alvo.Ip]
        $lojasRoteadorOk[$alvo.Loja] = $r.Respondeu
        $linhas += [PSCustomObject]@{
            Timestamp  = $timestamp
            Loja       = $alvo.Loja
            Tipo       = 'Roteador'
            Ip         = $alvo.Ip
            Respondeu  = $r.Respondeu
            LatenciaMs = $r.LatenciaMs
        }
    }

    # Pula a máquina quando o roteador da loja já falhou — está inacessível de
    # qualquer forma, e evitar o ping poupa o orçamento de tempo do ciclo.
    $maquinaAlvos = @($alvos | Where-Object { $_.Tipo -eq 'Maquina' })
    $maquinaParaTestar = @($maquinaAlvos | Where-Object {
        -not $lojasRoteadorOk.ContainsKey($_.Loja) -or $lojasRoteadorOk[$_.Loja]
    })
    $maquinaParaPular = @($maquinaAlvos | Where-Object {
        $lojasRoteadorOk.ContainsKey($_.Loja) -and -not $lojasRoteadorOk[$_.Loja]
    })

    $ipsMaquina = @($maquinaParaTestar | ForEach-Object { $_.Ip })
    $resultadosMaquina = Test-IpsParalelo -Ips $ipsMaquina -TimeoutMs $TimeoutMs

    foreach ($alvo in $maquinaParaTestar) {
        $r = $resultadosMaquina[$alvo.Ip]
        $linhas += [PSCustomObject]@{
            Timestamp  = $timestamp
            Loja       = $alvo.Loja
            Tipo       = 'Maquina'
            Ip         = $alvo.Ip
            Respondeu  = $r.Respondeu
            LatenciaMs = $r.LatenciaMs
        }
    }

    foreach ($alvo in $maquinaParaPular) {
        $linhas += [PSCustomObject]@{
            Timestamp  = $timestamp
            Loja       = $alvo.Loja
            Tipo       = 'Maquina'
            Ip         = $alvo.Ip
            Respondeu  = $null
            LatenciaMs = $null
        }
    }

    return $linhas
}

# --- Histórico CSV ---

function Add-HistoricoConectividade {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Linhas,
        [Parameter(Mandatory)] [string]$LogDir,
        [datetime]$Data = (Get-Date)
    )

    if ($Linhas.Count -eq 0) {
        return
    }

    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $arquivo = Join-Path $LogDir ("conectividade_{0}.csv" -f $Data.ToString('yyyy-MM-dd'))
    $Linhas | Export-Csv -Path $arquivo -NoTypeInformation -Append -Encoding UTF8
}

function Get-HistoricoDia {
    param(
        [Parameter(Mandatory)] [string]$LogDir,
        [datetime]$Data = (Get-Date)
    )

    $arquivo = Join-Path $LogDir ("conectividade_{0}.csv" -f $Data.ToString('yyyy-MM-dd'))
    if (-not (Test-Path $arquivo)) {
        return @()
    }
    return @(Import-Csv -Path $arquivo -Encoding UTF8)
}

# --- Estatísticas ---

function Get-EstatisticasLoja {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Historico,
        [Parameter(Mandatory)] [string]$Loja,
        [Parameter(Mandatory)] [ValidateSet('Roteador', 'Maquina')] [string]$Tipo
    )

    $linhas = @($Historico | Where-Object {
        $_.Loja -eq $Loja -and $_.Tipo -eq $Tipo -and $_.Respondeu -ne ''
    })
    $total = $linhas.Count
    $sucesso = @($linhas | Where-Object { $_.Respondeu -eq 'True' }).Count

    $uptimePct = if ($total -gt 0) { [math]::Round(($sucesso / $total) * 100) } else { 0 }

    $ultimaResposta = $linhas |
        Where-Object { $_.Respondeu -eq 'True' } |
        Sort-Object Timestamp -Descending |
        Select-Object -First 1 -ExpandProperty Timestamp

    return [PSCustomObject]@{
        UptimePct      = $uptimePct
        UltimaResposta = if ($ultimaResposta) { $ultimaResposta } else { '—' }
    }
}

# --- Painel HTML ---

function New-PainelHtml {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Resultados,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Lojas,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Historico,
        [string[]]$SemRoteador = @('E-COMMERCE'),
        [Parameter(Mandatory)] [string]$OutputPath
    )

    $atualizacao = (Get-Date).ToString('dd/MM/yyyy HH:mm:ss')
    $totalOk = 0
    $linhasHtml = @()

    foreach ($loja in $Lojas) {
        $rotulo = Get-LojaRotulo -Loja $loja
        $temRoteador = $rotulo -notin $SemRoteador

        $roteadorOk = $true
        $roteadorCell = 'N/A'
        if ($temRoteador) {
            $r = $Resultados | Where-Object { $_.Loja -eq $rotulo -and $_.Tipo -eq 'Roteador' } | Select-Object -First 1
            $roteadorOk = $r.Respondeu -eq $true
            $roteadorCell = if ($roteadorOk) { "🟢 $($r.LatenciaMs)ms" } else { '🟤' }
        }

        $m = $Resultados | Where-Object { $_.Loja -eq $rotulo -and $_.Tipo -eq 'Maquina' } | Select-Object -First 1
        $maquinaOk = $m.Respondeu -eq $true
        $maquinaCell = if ($null -eq $m.Respondeu) { 'N/A' } elseif ($maquinaOk) { "🟢 $($m.LatenciaMs)ms" } else { '🟤' }

        $statsM = Get-EstatisticasLoja -Historico $Historico -Loja $rotulo -Tipo 'Maquina'

        $linhaOk = $roteadorOk -and $maquinaOk
        if ($linhaOk) { $totalOk++ }
        $classe = if ($linhaOk) { 'ok' } else { 'problema' }

        $linhasHtml += "<tr class=`"$classe`"><td>$rotulo</td><td>$roteadorCell</td><td>$maquinaCell</td><td>$($statsM.UltimaResposta)</td><td>$($statsM.UptimePct)%</td></tr>"
    }

    $totalProblema = $Lojas.Count - $totalOk

    $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<title>Conectividade das Lojas</title>
<style>
body { font-family: Arial, sans-serif; margin: 20px; background: #faf6f0; color: #3a2f26; }
h1 { color: #3a5a40; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #8b6f47; padding: 6px 10px; text-align: center; }
th { background: #4a7c3f; color: #fff; }
tr.ok { background: #dff0d8; }
tr.problema { background: #e6d2b5; }
</style>
</head>
<body>
<h1>Conectividade das Lojas</h1>
<p>Última atualização: $atualizacao</p>
<p>OK: $totalOk &nbsp; | &nbsp; Com problema: $totalProblema</p>
<table>
<tr><th>Loja</th><th>Roteador</th><th>Máquina</th><th>Última resposta</th><th>Uptime hoje</th></tr>
$($linhasHtml -join "`n")
</table>
</body>
</html>
"@

    $outputDir = Split-Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $html | Out-File -FilePath $OutputPath -Encoding UTF8
}
