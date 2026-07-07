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
    $somaUptime = 0
    $linhasHtml = @()

    foreach ($loja in $Lojas) {
        $rotulo = Get-LojaRotulo -Loja $loja
        $temRoteador = $rotulo -notin $SemRoteador

        $roteadorOk = $true
        $roteadorCell = '<span class="na">N/A</span>'
        if ($temRoteador) {
            $r = $Resultados | Where-Object { $_.Loja -eq $rotulo -and $_.Tipo -eq 'Roteador' } | Select-Object -First 1
            $roteadorOk = $r.Respondeu -eq $true
            $roteadorCell = if ($roteadorOk) { "<span class=`"badge ok`">🟢 $($r.LatenciaMs)ms</span>" } else { '<span class="badge problema">🟤 offline</span>' }
        }

        $m = $Resultados | Where-Object { $_.Loja -eq $rotulo -and $_.Tipo -eq 'Maquina' } | Select-Object -First 1
        $maquinaOk = $m.Respondeu -eq $true
        $maquinaCell = if ($null -eq $m.Respondeu) { '<span class="na">N/A</span>' } elseif ($maquinaOk) { "<span class=`"badge ok`">🟢 $($m.LatenciaMs)ms</span>" } else { '<span class="badge problema">🟤 offline</span>' }

        $statsM = Get-EstatisticasLoja -Historico $Historico -Loja $rotulo -Tipo 'Maquina'
        $somaUptime += $statsM.UptimePct
        $ultimaRespostaFmt = $statsM.UltimaResposta
        [datetime]$comoData = [datetime]::MinValue
        if ([datetime]::TryParse($statsM.UltimaResposta, [ref]$comoData)) {
            $ultimaRespostaFmt = $comoData.ToString('HH:mm:ss')
        }

        $linhaOk = $roteadorOk -and $maquinaOk
        if ($linhaOk) { $totalOk++ }
        $classe = if ($linhaOk) { 'ok' } else { 'problema' }
        $barraCor = if ($statsM.UptimePct -ge 90) { '#4a7c3f' } elseif ($statsM.UptimePct -ge 50) { '#c9a227' } else { '#8b4a2b' }

        $linhasHtml += @"
<tr class="$classe">
  <td class="loja">$rotulo</td>
  <td>$roteadorCell</td>
  <td>$maquinaCell</td>
  <td class="hora">$ultimaRespostaFmt</td>
  <td class="uptime">
    <div class="uptime-track"><div class="uptime-fill" style="width:$($statsM.UptimePct)%;background:$barraCor;"></div></div>
    <span class="uptime-label">$($statsM.UptimePct)%</span>
  </td>
</tr>
"@
    }

    $totalProblema = $Lojas.Count - $totalOk
    $uptimeMedio = if ($Lojas.Count -gt 0) { [math]::Round($somaUptime / $Lojas.Count) } else { 0 }

    $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Conectividade das Lojas</title>
<style>
  :root {
    --verde-escuro: #2f4a34;
    --verde: #4a7c3f;
    --verde-claro: #dff0d8;
    --marrom: #8b6f47;
    --marrom-escuro: #5c4327;
    --marrom-claro: #e6d2b5;
    --fundo: #f4efe6;
    --card: #ffffff;
    --texto: #3a2f26;
    --texto-suave: #746a5c;
  }
  * { box-sizing: border-box; }
  body {
    font-family: "Segoe UI", system-ui, Arial, sans-serif;
    margin: 0;
    background: var(--fundo);
    color: var(--texto);
  }
  header {
    background: linear-gradient(135deg, var(--verde-escuro), var(--verde));
    color: #fff;
    padding: 24px 32px;
  }
  header h1 { margin: 0 0 4px 0; font-size: 1.5rem; }
  header a { color: #fff; }
  header p { margin: 0; opacity: 0.85; font-size: 0.9rem; }
  main { padding: 24px 32px 48px; max-width: 1200px; margin: 0 auto; }
  .cards {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 16px;
    margin-bottom: 28px;
  }
  .card {
    background: var(--card);
    border-radius: 12px;
    padding: 18px 20px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.08);
    border-left: 5px solid var(--marrom);
  }
  .card.verde { border-left-color: var(--verde); }
  .card.marrom { border-left-color: var(--marrom-escuro); }
  .card .valor { font-size: 1.9rem; font-weight: 700; line-height: 1.1; }
  .card .rotulo { font-size: 0.85rem; color: var(--texto-suave); margin-top: 4px; }
  .painel {
    background: var(--card);
    border-radius: 12px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.08);
    overflow: hidden;
  }
  table { border-collapse: collapse; width: 100%; }
  thead th {
    background: var(--verde-escuro);
    color: #fff;
    text-align: left;
    padding: 12px 16px;
    font-size: 0.8rem;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    position: sticky;
    top: 0;
  }
  td { padding: 10px 16px; border-bottom: 1px solid #eee5d8; font-size: 0.92rem; }
  tr:last-child td { border-bottom: none; }
  tr.problema { background: #fbf3e7; }
  tr:hover td { background: #f2ead9; }
  td.loja { font-weight: 600; }
  td.hora, td.uptime { color: var(--texto-suave); white-space: nowrap; }
  .badge {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 3px 10px;
    border-radius: 999px;
    font-size: 0.82rem;
    font-weight: 600;
  }
  .badge.ok { background: var(--verde-claro); color: var(--verde-escuro); }
  .badge.problema { background: var(--marrom-claro); color: var(--marrom-escuro); }
  .na { color: #b3a898; font-size: 0.82rem; }
  .uptime { display: flex; align-items: center; gap: 8px; }
  .uptime-track {
    width: 70px;
    height: 6px;
    background: #eee5d8;
    border-radius: 999px;
    overflow: hidden;
  }
  .uptime-fill { height: 100%; border-radius: 999px; }
  .uptime-label { font-weight: 600; min-width: 34px; }
  footer { text-align: center; padding: 20px; color: var(--texto-suave); font-size: 0.8rem; }
</style>
</head>
<body>
<header>
  <h1>Conectividade das Lojas</h1>
  <p>Última atualização: $atualizacao</p>
  <p><a href="ranking.html">Ver ranking de instabilidade →</a></p>
</header>
<main>
  <div class="cards">
    <div class="card verde">
      <div class="valor">$($Lojas.Count)</div>
      <div class="rotulo">Lojas monitoradas</div>
    </div>
    <div class="card verde">
      <div class="valor">$totalOk</div>
      <div class="rotulo">OK agora</div>
    </div>
    <div class="card marrom">
      <div class="valor">$totalProblema</div>
      <div class="rotulo">Com problema</div>
    </div>
    <div class="card">
      <div class="valor">$uptimeMedio%</div>
      <div class="rotulo">Uptime médio hoje</div>
    </div>
  </div>
  <div class="painel">
    <table>
      <thead>
        <tr><th>Loja</th><th>Roteador</th><th>Máquina</th><th>Última resposta</th><th>Uptime hoje</th></tr>
      </thead>
      <tbody>
        $($linhasHtml -join "`n")
      </tbody>
    </table>
  </div>
</main>
<footer>Atualiza automaticamente a cada 5 minutos, 8h–18h, dias úteis.</footer>
</body>
</html>
"@

    $outputDir = Split-Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($OutputPath, $html, $utf8Bom)
}

# --- Ranking de instabilidade ---

function Get-HistoricoPeriodo {
    param(
        [Parameter(Mandatory)] [string]$LogDir,
        [int]$Dias = 7,
        [datetime]$DataBase = (Get-Date)
    )

    $historico = @()
    for ($i = 0; $i -lt $Dias; $i++) {
        $data = $DataBase.AddDays(-$i)
        $historico += @(Get-HistoricoDia -LogDir $LogDir -Data $data)
    }
    return ,$historico
}

function Get-RankingInstabilidade {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Historico,
        [Parameter(Mandatory)] [ValidateSet('Roteador', 'Maquina')] [string]$Tipo,
        [int]$Top = 10
    )

    $porLoja = @($Historico | Where-Object { $_.Tipo -eq $Tipo -and $_.Respondeu -ne '' } | Group-Object Loja)

    $ranking = foreach ($grupo in $porLoja) {
        $total = $grupo.Count
        $quedas = @($grupo.Group | Where-Object { $_.Respondeu -eq 'False' })
        $pctQueda = [math]::Round(($quedas.Count / $total) * 100)

        $horarioPico = '—'
        $horaMaisComum = $quedas | ForEach-Object {
            [datetime]$dt = [datetime]::MinValue
            if ([datetime]::TryParse($_.Timestamp, [ref]$dt)) { $dt.Hour }
        } | Group-Object | Sort-Object Count -Descending | Select-Object -First 1

        if ($horaMaisComum) {
            $hora = [int]$horaMaisComum.Name
            $horaFim = ($hora + 1) % 24
            $horarioPico = "{0:D2}h–{1:D2}h" -f $hora, $horaFim
        }

        [PSCustomObject]@{
            Loja        = $grupo.Name
            PctQueda    = $pctQueda
            HorarioPico = $horarioPico
        }
    }

    return ,@($ranking | Sort-Object PctQueda -Descending | Select-Object -First $Top)
}

function Get-RankingLatencia {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$Historico,
        [int]$Top = 10
    )

    $porLoja = @($Historico | Where-Object { $_.Respondeu -eq 'True' -and $_.LatenciaMs -ne '' } | Group-Object Loja)

    $ranking = foreach ($grupo in $porLoja) {
        $latencias = $grupo.Group | ForEach-Object { [double]$_.LatenciaMs }
        $media = [math]::Round(($latencias | Measure-Object -Average).Average)

        [PSCustomObject]@{
            Loja            = $grupo.Name
            LatenciaMediaMs = $media
        }
    }

    return ,@($ranking | Sort-Object LatenciaMediaMs -Descending | Select-Object -First $Top)
}

function New-RankingHtml {
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$RankingRoteador,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$RankingMaquina,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [array]$RankingLatencia,
        [int]$Dias = 7,
        [Parameter(Mandatory)] [string]$OutputPath
    )

    $atualizacao = (Get-Date).ToString('dd/MM/yyyy HH:mm:ss')

    $linhasRoteador = if ($RankingRoteador.Count -eq 0) {
        '<tr><td colspan="3" class="vazio">Sem dados suficientes ainda</td></tr>'
    } else {
        ($RankingRoteador | ForEach-Object { "<tr><td class=`"loja`">$($_.Loja)</td><td>$($_.PctQueda)%</td><td>$($_.HorarioPico)</td></tr>" }) -join "`n"
    }

    $linhasMaquina = if ($RankingMaquina.Count -eq 0) {
        '<tr><td colspan="3" class="vazio">Sem dados suficientes ainda</td></tr>'
    } else {
        ($RankingMaquina | ForEach-Object { "<tr><td class=`"loja`">$($_.Loja)</td><td>$($_.PctQueda)%</td><td>$($_.HorarioPico)</td></tr>" }) -join "`n"
    }

    $linhasLatencia = if ($RankingLatencia.Count -eq 0) {
        '<tr><td colspan="2" class="vazio">Sem dados suficientes ainda</td></tr>'
    } else {
        ($RankingLatencia | ForEach-Object { "<tr><td class=`"loja`">$($_.Loja)</td><td>$($_.LatenciaMediaMs)ms</td></tr>" }) -join "`n"
    }

    $html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Ranking de Instabilidade — Lojas</title>
<style>
  :root {
    --verde-escuro: #2f4a34;
    --verde: #4a7c3f;
    --marrom: #8b6f47;
    --marrom-escuro: #5c4327;
    --fundo: #f4efe6;
    --card: #ffffff;
    --texto: #3a2f26;
    --texto-suave: #746a5c;
  }
  * { box-sizing: border-box; }
  body { font-family: "Segoe UI", system-ui, Arial, sans-serif; margin: 0; background: var(--fundo); color: var(--texto); }
  header { background: linear-gradient(135deg, var(--verde-escuro), var(--verde)); color: #fff; padding: 24px 32px; }
  header h1 { margin: 0 0 4px 0; font-size: 1.5rem; }
  header p { margin: 4px 0 0; opacity: 0.85; font-size: 0.9rem; }
  header a { color: #fff; }
  main {
    padding: 24px 32px 48px;
    max-width: 1200px;
    margin: 0 auto;
    display: grid;
    gap: 24px;
    grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
  }
  .painel { background: var(--card); border-radius: 12px; box-shadow: 0 1px 3px rgba(0,0,0,0.08); overflow: hidden; }
  .painel h2 { margin: 0; padding: 14px 16px; background: var(--verde-escuro); color: #fff; font-size: 1rem; }
  table { border-collapse: collapse; width: 100%; }
  th { text-align: left; padding: 8px 16px; font-size: 0.75rem; text-transform: uppercase; color: var(--texto-suave); border-bottom: 1px solid #eee5d8; }
  td { padding: 8px 16px; border-bottom: 1px solid #eee5d8; font-size: 0.9rem; }
  tr:last-child td { border-bottom: none; }
  td.loja { font-weight: 600; }
  td.vazio { color: var(--texto-suave); text-align: center; padding: 20px; }
</style>
</head>
<body>
<header>
  <h1>Ranking de Instabilidade das Lojas</h1>
  <p>Últimos $Dias dias — atualizado em $atualizacao</p>
  <p><a href="conectividade.html">← Voltar ao painel</a></p>
</header>
<main>
  <div class="painel">
    <h2>Mais quedas — Roteador</h2>
    <table>
      <tr><th>Loja</th><th>% fora</th><th>Horário mais comum</th></tr>
      $linhasRoteador
    </table>
  </div>
  <div class="painel">
    <h2>Mais quedas — Máquina</h2>
    <table>
      <tr><th>Loja</th><th>% fora</th><th>Horário mais comum</th></tr>
      $linhasMaquina
    </table>
  </div>
  <div class="painel">
    <h2>Mais lentas</h2>
    <table>
      <tr><th>Loja</th><th>Latência média</th></tr>
      $linhasLatencia
    </table>
  </div>
</main>
</body>
</html>
"@

    $outputDir = Split-Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($OutputPath, $html, $utf8Bom)
}