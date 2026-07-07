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
