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
        [Parameter(Mandatory)] [array]$Lojas,
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

    $tarefas = @{}
    foreach ($ip in $Ips) {
        $ping = [System.Net.NetworkInformation.Ping]::new()
        $tarefas[$ip] = $ping.SendPingAsync($ip, $TimeoutMs)
    }
    [System.Threading.Tasks.Task]::WaitAll(@($tarefas.Values))

    foreach ($ip in $Ips) {
        $reply = $tarefas[$ip].Result
        $sucesso = $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success
        $resultados[$ip] = [PSCustomObject]@{
            Respondeu  = $sucesso
            LatenciaMs = if ($sucesso) { $reply.RoundtripTime } else { $null }
        }
    }
    return $resultados
}
