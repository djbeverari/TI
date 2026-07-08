# Gerar Painel Web - Data Sync
# Atualiza painel HTML em tempo real com status das sincronizacoes

$paineFile = "C:\Logs\DataSync\painel.html"

function Gerar-Painel {
    $logFileHoje = "C:\Logs\DataSync\sync_$(Get-Date -Format 'yyyy-MM-dd').log"
    $totalSucesso    = 0
    $totalFalha      = 0
    $ultimaExecucao  = $null
    $ultimoStatus    = "Desconhecido"
    $lojasFalhaRecebe = @()
    $lojasFalhaEnvia  = @()

    # Ler status em tempo real dos arquivos por loja
    $todasLojas  = @(3,4,5,6,7,9,14,16,17,21,23,26,28,29,31,32,33,34,36,37,38,40,41,42,44,45,46,47,48,49,50,51,52,53,54,55,56,57)
    $statusLojas = @{}
    $statusDir   = "C:\Logs\DataSync\status"
    $hoje        = (Get-Date).Date
    if (Test-Path $statusDir) {
        Get-ChildItem "$statusDir\loja_*.txt" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $hoje } |
        ForEach-Object {
            if ($_.Name -match 'loja_([^.]+)\.txt') {
                $num = $matches[1]
                $c = Get-Content $_.FullName -Encoding UTF8 -ErrorAction SilentlyContinue
                if ($c -match '^(\w+)\|(\w+)\|(.*)$') {
                    $statusLojas[$num] = @{ Tipo=$matches[1]; Status=$matches[2]; Hora=$matches[3] }
                }
            }
        }
    }

    if(Test-Path $logFileHoje) {
        $linhas = @(Get-Content $logFileHoje -Encoding UTF8 2>$null)

        # Encontrar o indice do ultimo ciclo iniciado
        $ultimoInicioIdx = -1
        for ($i = 0; $i -lt $linhas.Count; $i++) {
            if ($linhas[$i] -match 'SINCRONIZANDO \d+ LOJAS') { $ultimoInicioIdx = $i }
        }

        if ($ultimoInicioIdx -ge 0) {
            # Extrair timestamp do inicio do ultimo ciclo
            if ($linhas[$ultimoInicioIdx] -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]') {
                $ultimaExecucao = [datetime]::ParseExact($matches[1], 'yyyy-MM-dd HH:mm:ss', $null)
            }

            # Analisar apenas o ultimo bloco
            $ultimoBloco = $linhas[$ultimoInicioIdx..($linhas.Count - 1)]

            $ultimoBloco | ForEach-Object {
                if ($_ -match '\[ERROR\].*Loja (\d+) - RECEBE') {
                    $lojasFalhaRecebe += $matches[1]
                }
                if ($_ -match '\[ERROR\].*Loja (\d+) - ENVIA') {
                    $lojasFalhaEnvia += $matches[1]
                }
                if ($_ -match '\[OK\] Lojas com sucesso: (\d+)')     { $totalSucesso = [int]$matches[1] }
                if ($_ -match '\[ERRO\] Lojas com falha: (\d+)')   { $totalFalha   = [int]$matches[1] }
            }

            if ($totalFalha -eq 0 -and $totalSucesso -gt 0)    { $ultimoStatus = "SUCESSO" }
            elseif ($totalFalha -gt 0 -and $totalSucesso -gt 0) { $ultimoStatus = "PARCIAL" }
            elseif ($totalFalha -gt 0 -and $totalSucesso -eq 0) { $ultimoStatus = "FALHA" }
        }
    }

    # Calcular tempo desde ultima sincronizacao
    $tempoDecorrido = "Sem registro hoje"
    $corStatus      = "#999"
    if ($ultimaExecucao) {
        $diff = (Get-Date) - $ultimaExecucao
        if     ($diff.TotalMinutes -lt 60) { $tempoDecorrido = "$([int]$diff.TotalMinutes) min atras" }
        elseif ($diff.TotalHours   -lt 24) { $tempoDecorrido = "$([int]$diff.TotalHours)h atras" }
        else                               { $tempoDecorrido = "$([int]$diff.TotalDays)d atras" }

        $corStatus = switch ($ultimoStatus) {
            "SUCESSO" { "#4CAF50" }
            "PARCIAL" { "#ff9800" }
            "FALHA"   { "#f44336" }
            default   { "#999" }
        }
    }

    # Montar lista de lojas com problema por tipo
    $todasFalhadas = @($lojasFalhaRecebe + $lojasFalhaEnvia) | Sort-Object -Unique

    # Contagem em tempo real dos arquivos de status (durante o ciclo)
    $errosRealTime = @($statusLojas.GetEnumerator() | Where-Object { $_.Value.Status -eq "ERRO" } | ForEach-Object { $_.Key })
    $okEnviaRealTime = ($statusLojas.Values | Where-Object { $_.Status -eq "OK" -and $_.Tipo -eq "ENVIA" }).Count

    # Usa resumo do log se disponivel (fim de ciclo), senao usa status em tempo real
    $exibeFalha   = if ($totalFalha   -gt 0) { $totalFalha }   else { $errosRealTime.Count }
    $exibeSucesso = if ($totalSucesso -gt 0) { $totalSucesso } else { $okEnviaRealTime }

    # Construir HTML
    $sb = New-Object System.Text.StringBuilder

    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="pt-BR">')
    [void]$sb.AppendLine('<head>')
    [void]$sb.AppendLine('    <meta charset="UTF-8">')
    [void]$sb.AppendLine('    <meta name="viewport" content="width=device-width, initial-scale=1.0">')
    [void]$sb.AppendLine('    <title>Data Sync - Painel de Monitoramento</title>')
    [void]$sb.AppendLine('    <style>')
    [void]$sb.AppendLine('        * { margin: 0; padding: 0; box-sizing: border-box; }')
    [void]$sb.AppendLine('        body {')
    [void]$sb.AppendLine('            font-family: "Segoe UI", Tahoma, Geneva, Verdana, sans-serif;')
    [void]$sb.AppendLine('            background: linear-gradient(135deg, #001a4d 0%, #003d82 100%);')
    [void]$sb.AppendLine('            min-height: 100vh; padding: 20px; color: #333;')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('        .container { max-width: 1200px; margin: 0 auto; }')
    [void]$sb.AppendLine('        header { text-align: center; color: white; margin-bottom: 30px; }')
    [void]$sb.AppendLine('        h1 { font-size: 2.5em; margin-bottom: 10px; text-shadow: 2px 2px 4px rgba(0,0,0,0.3); }')
    [void]$sb.AppendLine('        .timestamp { color: rgba(255,255,255,0.9); font-size: 0.95em; }')
    [void]$sb.AppendLine('        .status-grid {')
    [void]$sb.AppendLine('            display: grid;')
    [void]$sb.AppendLine('            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));')
    [void]$sb.AppendLine('            gap: 20px; margin-bottom: 30px;')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('        .card {')
    [void]$sb.AppendLine('            background: white; border-radius: 10px; padding: 25px;')
    [void]$sb.AppendLine('            box-shadow: 0 10px 30px rgba(0,0,0,0.2); transition: transform 0.3s ease;')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('        .card:hover { transform: translateY(-5px); }')
    [void]$sb.AppendLine('        .card-title { font-size: 0.9em; color: #999; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 10px; }')
    [void]$sb.AppendLine('        .card-value { font-size: 2.5em; font-weight: bold; margin-bottom: 5px; }')
    [void]$sb.AppendLine('        .card-status { font-size: 0.85em; padding: 5px 10px; border-radius: 5px; display: inline-block; }')
    [void]$sb.AppendLine('        .success { background: #4CAF50; color: white; }')
    [void]$sb.AppendLine('        .error   { background: #f44336; color: white; }')
    [void]$sb.AppendLine('        .warning { background: #ff9800; color: white; }')
    [void]$sb.AppendLine('        .info-card {')
    [void]$sb.AppendLine('            background: white; border-radius: 10px; padding: 25px;')
    [void]$sb.AppendLine('            box-shadow: 0 10px 30px rgba(0,0,0,0.2); margin-bottom: 30px;')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('        .info-title {')
    [void]$sb.AppendLine('            font-size: 1.3em; font-weight: bold; margin-bottom: 15px;')
    [void]$sb.AppendLine('            color: #003d82; border-bottom: 3px solid #003d82; padding-bottom: 10px;')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('        .alert-list { list-style: none; }')
    [void]$sb.AppendLine('        .alert-item {')
    [void]$sb.AppendLine('            background: #f9f9f9; padding: 15px; margin-bottom: 10px;')
    [void]$sb.AppendLine('            border-left: 5px solid #ff9800; border-radius: 5px;')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('        .alert-loja { font-weight: bold; color: #333; font-size: 1.05em; }')
    [void]$sb.AppendLine('        .badge {')
    [void]$sb.AppendLine('            display: inline-block; font-size: 0.8em; padding: 2px 8px;')
    [void]$sb.AppendLine('            border-radius: 4px; color: white; margin-left: 6px; font-weight: bold;')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('        .badge-recebe { background: #9c27b0; }')
    [void]$sb.AppendLine('        .badge-envia  { background: #f44336; }')
    [void]$sb.AppendLine('        .footer { text-align: center; color: white; margin-top: 40px; font-size: 0.9em; }
        .progress-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(95px, 1fr));
            gap: 8px; margin-top: 15px;
        }
        .sc {
            background: white; border-radius: 8px; padding: 10px 6px;
            text-align: center; box-shadow: 0 3px 10px rgba(0,0,0,0.12);
            border-top: 4px solid #e0e0e0; transition: transform 0.2s;
        }
        .sc:hover { transform: translateY(-2px); }
        .sc-num    { font-weight: bold; font-size: 0.95em; color: #333; }
        .sc-fase   { font-size: 0.68em; text-transform: uppercase; letter-spacing: 0.5px; margin-top: 4px; }
        .sc-hora   { font-size: 0.62em; color: #999; margin-top: 2px; }
        .sc-rodando  { border-top-color: #2196F3; background: #f0f7ff; }
        .sc-ok-r     { border-top-color: #8BC34A; }
        .sc-ok       { border-top-color: #4CAF50; background: #f5fff5; }
        .sc-erro     { border-top-color: #f44336; background: #fff5f5; }
        .sc-ignorado { border-top-color: #9e9e9e; background: #f9f9f9; }
        .sc-aguard   { border-top-color: #e0e0e0; }
        @keyframes piscar { 0%,100%{opacity:1} 50%{opacity:0.5} }
        .sc-rodando { animation: piscar 1.2s infinite; }')
    [void]$sb.AppendLine('        .status-indicator {')
    [void]$sb.AppendLine('            display: inline-block; width: 12px; height: 12px;')
    [void]$sb.AppendLine('            border-radius: 50%; margin-right: 8px; animation: pulse 2s infinite;')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('        .status-indicator.online  { background: #4CAF50; }')
    [void]$sb.AppendLine('        .status-indicator.offline { background: #f44336; }')
    [void]$sb.AppendLine('        @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }')
    [void]$sb.AppendLine('        @media (max-width: 768px) {')
    [void]$sb.AppendLine('            h1 { font-size: 1.8em; }')
    [void]$sb.AppendLine('            .card-value { font-size: 1.8em; }')
    [void]$sb.AppendLine('            .status-grid { grid-template-columns: 1fr; }')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('    </style>')
    [void]$sb.AppendLine('</head>')
    [void]$sb.AppendLine('<body>')
    [void]$sb.AppendLine('    <div class="container">')
    [void]$sb.AppendLine('        <header>')
    [void]$sb.AppendLine('            <h1>Data Sync - Painel de Monitoramento</h1>')
    [void]$sb.AppendLine("            <p class='timestamp' style='font-size:0.9em; opacity:0.85; margin-top:4px;'>Agente: <strong>Clebson</strong></p>")
    $ultimaSincStr = if ($ultimaExecucao) { $ultimaExecucao.ToString('dd/MM/yyyy HH:mm:ss') } else { "Nenhuma hoje" }
    [void]$sb.AppendLine("            <p class='timestamp'>Painel atualizado: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')</p>")
    [void]$sb.AppendLine("            <p class='timestamp' style='font-size:0.95em; margin-top:8px;'>&Uacute;ltima sincroniza&ccedil;&atilde;o: <strong>$ultimaSincStr</strong> &nbsp;|&nbsp; $tempoDecorrido</p>")
    [void]$sb.AppendLine('        </header>')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('        <div class="status-grid">')

    # Card: Status Geral
    [void]$sb.AppendLine('            <div class="card">')
    [void]$sb.AppendLine('                <div class="card-title">Status Geral</div>')
    [void]$sb.AppendLine('                <div class="card-value"><span class="status-indicator online"></span>ATIVO</div>')
    [void]$sb.AppendLine('                <div class="card-status success">Monitorando 24/7</div>')
    [void]$sb.AppendLine('            </div>')

    # Card: Ultima Sincronizacao
    [void]$sb.AppendLine('            <div class="card">')
    [void]$sb.AppendLine('                <div class="card-title">&Uacute;ltima Sincroniza&ccedil;&atilde;o</div>')
    $ultimaSincCard = if ($ultimaExecucao) { $ultimaExecucao.ToString('HH:mm') } else { "--:--" }
    $dataSincCard   = if ($ultimaExecucao) { $ultimaExecucao.ToString('dd/MM') } else { "sem dados" }
    $cssStatus      = switch ($ultimoStatus) { "SUCESSO"{"success"} "PARCIAL"{"warning"} "FALHA"{"error"} default{"warning"} }
    [void]$sb.AppendLine("                <div class='card-value' style='color:$corStatus; font-size:2em;'>$ultimaSincCard</div>")
    [void]$sb.AppendLine("                <div style='font-size:0.85em; color:#666; margin-bottom:8px;'>$dataSincCard &nbsp;&bull;&nbsp; $tempoDecorrido</div>")
    [void]$sb.AppendLine("                <div class='card-status $cssStatus'>$ultimoStatus</div>")
    [void]$sb.AppendLine('            </div>')

    # Card: Lojas com Sucesso
    [void]$sb.AppendLine('            <div class="card">')
    [void]$sb.AppendLine('                <div class="card-title">Lojas com Sucesso</div>')
    [void]$sb.AppendLine("                <div class='card-value' style='color:#4CAF50;'>$exibeSucesso</div>")
    [void]$sb.AppendLine("                <div style='font-size:0.85em; color:#666; margin-bottom:8px;'>$dataSincCard &nbsp;&bull;&nbsp; $ultimaSincCard</div>")
    [void]$sb.AppendLine('                <div class="card-status success">Sincronizadas</div>')
    [void]$sb.AppendLine('            </div>')

    # Card: Lojas com Falha
    [void]$sb.AppendLine('            <div class="card">')
    [void]$sb.AppendLine('                <div class="card-title">Lojas com Falha</div>')
    [void]$sb.AppendLine("                <div class='card-value' style='color:#f44336;'>$exibeFalha</div>")
    [void]$sb.AppendLine("                <div style='font-size:0.85em; color:#666; margin-bottom:8px;'>$dataSincCard &nbsp;&bull;&nbsp; $ultimaSincCard</div>")
    [void]$sb.AppendLine('                <div class="card-status error">Requer Aten&ccedil;&atilde;o</div>')
    [void]$sb.AppendLine('            </div>')
    [void]$sb.AppendLine('        </div>')

    # Secao: Progresso em tempo real
    [void]$sb.AppendLine('        <div class="info-card">')
    [void]$sb.AppendLine('            <div class="info-title">Progresso do Ciclo</div>')
    [void]$sb.AppendLine('            <div class="progress-grid">')

    foreach ($NumeroLoja in $todasLojas) {
        $Loja = "{0:D2}" -f $NumeroLoja
        if ($statusLojas.ContainsKey($Loja)) {
            $s = $statusLojas[$Loja]
            $cssClass = switch ($s.Status) {
                "RODANDO"  { "sc-rodando" }
                "OK"       { if ($s.Tipo -eq "RECEBE") { "sc-ok-r" } else { "sc-ok" } }
                "ERRO"     { "sc-erro" }
                "IGNORADO" { "sc-ignorado" }
                default    { "sc-aguard" }
            }
            $faseLabel = switch ("$($s.Tipo)|$($s.Status)") {
                "RECEBE|RODANDO"  { "RECEBE..." }
                "RECEBE|OK"       { "RECEBE OK" }
                "RECEBE|ERRO"     { "RECEBE ERRO" }
                "ENVIA|RODANDO"   { "ENVIA..." }
                "ENVIA|OK"        { "ENVIA OK" }
                "ENVIA|ERRO"      { "ENVIA ERRO" }
                "ENVIA|IGNORADO"  { "ENVIA pulado" }
                default           { "$($s.Tipo) $($s.Status)" }
            }
            [void]$sb.AppendLine("            <div class='sc $cssClass'><div class='sc-num'>Loja $Loja</div><div class='sc-fase'>$faseLabel</div><div class='sc-hora'>$($s.Hora)</div></div>")
        } else {
            [void]$sb.AppendLine("            <div class='sc sc-aguard'><div class='sc-num'>Loja $Loja</div><div class='sc-fase'>aguardando</div><div class='sc-hora'>&nbsp;</div></div>")
        }
    }

    # E-Commerce
    $Loja = "E-COMMERCE"
    if ($statusLojas.ContainsKey($Loja)) {
        $s = $statusLojas[$Loja]
        $cssClass = switch ($s.Status) {
            "RODANDO"  { "sc-rodando" }
            "OK"       { if ($s.Tipo -eq "RECEBE") { "sc-ok-r" } else { "sc-ok" } }
            "ERRO"     { "sc-erro" }
            "IGNORADO" { "sc-ignorado" }
            default    { "sc-aguard" }
        }
        $faseLabel = switch ("$($s.Tipo)|$($s.Status)") {
            "RECEBE|RODANDO"  { "RECEBE..." }
            "RECEBE|OK"       { "RECEBE OK" }
            "RECEBE|ERRO"     { "RECEBE ERRO" }
            "ENVIA|RODANDO"   { "ENVIA..." }
            "ENVIA|OK"        { "ENVIA OK" }
            "ENVIA|ERRO"      { "ENVIA ERRO" }
            "ENVIA|IGNORADO"  { "ENVIA pulado" }
            default           { "$($s.Tipo) $($s.Status)" }
        }
        [void]$sb.AppendLine("            <div class='sc $cssClass'><div class='sc-num'>E-Commerce</div><div class='sc-fase'>$faseLabel</div><div class='sc-hora'>$($s.Hora)</div></div>")
    } else {
        [void]$sb.AppendLine("            <div class='sc sc-aguard'><div class='sc-num'>E-Commerce</div><div class='sc-fase'>aguardando</div><div class='sc-hora'>&nbsp;</div></div>")
    }

    [void]$sb.AppendLine('            </div>')
    [void]$sb.AppendLine('        </div>')

    # Secao: Lojas com Problemas (ultima sincronizacao)
    [void]$sb.AppendLine('        <div class="info-card">')
    [void]$sb.AppendLine('            <div class="info-title">Lojas com Problema &mdash; &uacute;ltima sincroniza&ccedil;&atilde;o</div>')
    [void]$sb.AppendLine('            <ul class="alert-list">')

    if ($todasFalhadas.Count -gt 0) {
        $todasFalhadas | ForEach-Object {
            $loja = $_
            $badges = ""
            if ($lojasFalhaRecebe -contains $loja) { $badges += "<span class='badge badge-recebe'>RECEBE</span>" }
            if ($lojasFalhaEnvia  -contains $loja) { $badges += "<span class='badge badge-envia'>ENVIA</span>" }
            [void]$sb.AppendLine("                <li class='alert-item'>")
            [void]$sb.AppendLine("                    <span class='alert-loja'>Loja $loja</span>$badges")
            [void]$sb.AppendLine("                </li>")
        }
    } else {
        [void]$sb.AppendLine('                <li class="alert-item" style="border-left-color:#4CAF50; background:#f5fff5;">')
        [void]$sb.AppendLine('                    <span style="color:#4CAF50; font-weight:bold;">OK &mdash; Nenhuma loja com erro na &uacute;ltima sincroniza&ccedil;&atilde;o</span>')
        [void]$sb.AppendLine('                </li>')
    }

    [void]$sb.AppendLine('            </ul>')
    [void]$sb.AppendLine('        </div>')

    # Secao: Informacoes do Sistema
    [void]$sb.AppendLine('        <div class="info-card">')
    [void]$sb.AppendLine('            <div class="info-title">Informa&ccedil;&otilde;es do Sistema</div>')
    [void]$sb.AppendLine('            <ul class="alert-list">')
    [void]$sb.AppendLine('                <li class="alert-item">')
    [void]$sb.AppendLine('                    <strong>Modo de Opera&ccedil;&atilde;o:</strong><br>')
    [void]$sb.AppendLine('                    Sincroniza&ccedil;&otilde;es agendadas (10:30, 14:30, 16:30) de segunda a sexta-feira')
    [void]$sb.AppendLine('                </li>')
    [void]$sb.AppendLine('                <li class="alert-item">')
    [void]$sb.AppendLine('                    <strong>Processo:</strong><br>')
    [void]$sb.AppendLine('                    RECEBE (todas as 38 lojas) + 15 minutos de pausa + ENVIA (lojas com RECEBE ok)')
    [void]$sb.AppendLine('                </li>')
    [void]$sb.AppendLine('                <li class="alert-item">')
    [void]$sb.AppendLine('                    <strong>Monitoramento:</strong><br>')
    [void]$sb.AppendLine('                    Ativo 24/7 com detec&ccedil;&atilde;o autom&aacute;tica de falhas')
    [void]$sb.AppendLine('                </li>')
    [void]$sb.AppendLine('            </ul>')
    [void]$sb.AppendLine('        </div>')

    [void]$sb.AppendLine('        <footer>')
    [void]$sb.AppendLine('            <p>Painel se atualiza automaticamente a cada 30 segundos</p>')
    [void]$sb.AppendLine("            <p style='margin-top:10px; opacity:0.8;'>Data Sync Automa&ccedil;&atilde;o &mdash; Monitoramento Cont&iacute;nuo</p>")
    [void]$sb.AppendLine('        </footer>')
    [void]$sb.AppendLine('    </div>')
    [void]$sb.AppendLine('    <script>')
    [void]$sb.AppendLine('        setInterval(function() { location.reload(); }, 30000);')
    [void]$sb.AppendLine('    </script>')
    [void]$sb.AppendLine('</body>')
    [void]$sb.AppendLine('</html>')

    $utf8NoBOM = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($paineFile, $sb.ToString(), $utf8NoBOM)
    Write-Host "Painel atualizado: $paineFile"
}

# Executar uma vez
Gerar-Painel

# Loop continuo
while($true) {
    Start-Sleep -Seconds 30
    Gerar-Painel
}
