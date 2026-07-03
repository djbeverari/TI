# =====================================================================
# tickets-lib.ps1 — Biblioteca de funções do Verificador de Tickets
# Funções puras (testáveis com Pester) + funções finas de I/O.
# Dot-source: . .\scripts\tickets-lib.ps1
# =====================================================================

# ---------------------------------------------------------------------
# Classificação de status de uma loja.
# Regra: origem é a LOJA. Alerta quando a retaguarda tem MENOS que a loja.
# ---------------------------------------------------------------------
function Get-TicketStatus {
    param(
        [int]$TicketsLoja,
        [int]$TicketsRetaguarda,
        [bool]$SyncConcluido,
        [bool]$ErroConexao
    )
    if ($ErroConexao) { return 'ERRO' }
    if ($TicketsLoja -eq 0 -and $TicketsRetaguarda -eq 0) { return 'SEM_MOVIMENTO' }
    if ($TicketsRetaguarda -eq $TicketsLoja) { return 'OK' }
    if ($TicketsRetaguarda -gt $TicketsLoja) { return 'ATENCAO' }
    # Retaguarda < Loja: ticket da loja não chegou
    if ($SyncConcluido) { return 'DIVERGENTE' } else { return 'PENDENTE' }
}

# ---------------------------------------------------------------------
# Datas a verificar, considerando fim de semana e feriados.
# ---------------------------------------------------------------------
function Test-DiaUtil {
    param([datetime]$Data, [datetime[]]$Feriados = @())
    if ($Data.DayOfWeek -eq 'Saturday' -or $Data.DayOfWeek -eq 'Sunday') { return $false }
    foreach ($f in $Feriados) { if ($f.Date -eq $Data.Date) { return $false } }
    return $true
}

function Get-DatasParaVerificar {
    param([datetime]$Referencia, [datetime[]]$Feriados = @())
    # Último dia útil antes da referência
    $prev = $Referencia.Date.AddDays(-1)
    while (-not (Test-DiaUtil -Data $prev -Feriados $Feriados)) { $prev = $prev.AddDays(-1) }
    # Todas as datas de $prev até o dia anterior à referência (inclusive)
    $datas = @()
    $d = $prev
    while ($d -lt $Referencia.Date) { $datas += $d; $d = $d.AddDays(1) }
    return $datas
}

# ---------------------------------------------------------------------
# Feriados municipais (por loja) a partir do CSV mantido à mão.
# ---------------------------------------------------------------------
function Get-FeriadosMunicipais {
    param([string]$Csv, [int]$Loja)
    if (-not (Test-Path $Csv)) { return @() }
    $datas = @()
    foreach ($linha in Import-Csv -Path $Csv) {
        $lojas = $linha.LOJAS
        $vale = ($lojas -eq 'TODAS') -or (($lojas -split '\|') -contains "$Loja")
        if ($vale) { $datas += [datetime]::ParseExact($linha.DATA, 'yyyy-MM-dd', $null) }
    }
    return $datas
}

# ---------------------------------------------------------------------
# Feriados nacionais via Brasil API, com cache anual e fallback fixo.
# ---------------------------------------------------------------------
function Get-FeriadosNacionais {
    param([int]$Ano, [string]$CacheFile)
    if (Test-Path $CacheFile) {
        $cache = Get-Content $CacheFile -Raw | ConvertFrom-Json
        if ($cache.PSObject.Properties.Name -contains "$Ano") {
            return @($cache."$Ano" | ForEach-Object { [datetime]$_ })
        }
    } else {
        $cache = [pscustomobject]@{}
    }
    try {
        $resp = Invoke-RestMethod -Uri "https://brasilapi.com.br/api/feriados/v1/$Ano" -TimeoutSec 20
        $datas = $resp | ForEach-Object { $_.date }
        $cache | Add-Member -NotePropertyName "$Ano" -NotePropertyValue $datas -Force
        $cache | ConvertTo-Json | Set-Content $CacheFile -Encoding UTF8
        return @($datas | ForEach-Object { [datetime]$_ })
    } catch {
        # Fallback: feriados nacionais fixos (móveis como Carnaval/Corpus Christi ficam de fora)
        return @(
            [datetime]"$Ano-01-01", [datetime]"$Ano-04-21", [datetime]"$Ano-05-01",
            [datetime]"$Ano-09-07", [datetime]"$Ano-10-12", [datetime]"$Ano-11-02",
            [datetime]"$Ano-11-15", [datetime]"$Ano-12-25"
        )
    }
}

# ---------------------------------------------------------------------
# Contagem de tickets num banco (loja ou retaguarda) via ADO.NET.
# Quem chama deve envolver em try/catch (loja offline -> status ERRO).
# ---------------------------------------------------------------------
function Get-TicketCount {
    param(
        [string]$Servidor, [string]$Banco, [string]$Usuario, [string]$Senha,
        [datetime[]]$Datas, [string]$ColunaLoja, [int]$Loja, [int]$TimeoutSec = 20
    )
    $inList = ($Datas | ForEach-Object { "'" + $_.ToString('yyyy-MM-dd') + "'" }) -join ','
    $where = "data_venda IN ($inList)"
    if ($ColunaLoja) { $where += " AND [$ColunaLoja] = $Loja" }
    $sql = "SELECT COUNT(*) FROM loja_venda WHERE $where"
    $cs  = "Server=$Servidor;Database=$Banco;User Id=$Usuario;Password=$Senha;Connect Timeout=$TimeoutSec"
    $cn  = New-Object System.Data.SqlClient.SqlConnection $cs
    try {
        $cn.Open()
        $cmd = $cn.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = $TimeoutSec
        return [int]$cmd.ExecuteScalar()
    } finally { $cn.Close() }
}

# ---------------------------------------------------------------------
# A loja já concluiu o sync de hoje? (lê o status do datasync)
# Formato gravado pelo data-sync-automacao.ps1 em C:\Logs\DataSync\status:
#   arquivo loja_<num>.txt  conteúdo "Tipo|Status|Hora" (ex.: ENVIA|OK|16:32)
# Considera concluído = arquivo de hoje com Status = OK.
# ---------------------------------------------------------------------
function Get-SyncConcluidoLoja {
    param([int]$Loja, [string]$StatusDir, [datetime]$Hoje = (Get-Date))
    # Tolera nome com e sem zero à esquerda (loja_3.txt / loja_03.txt)
    $candidatos = @(
        (Join-Path $StatusDir ("loja_{0}.txt"    -f $Loja)),
        (Join-Path $StatusDir ("loja_{0:D2}.txt" -f $Loja))
    ) | Select-Object -Unique
    foreach ($arquivo in $candidatos) {
        if (-not (Test-Path $arquivo)) { continue }
        if ((Get-Item $arquivo).LastWriteTime.Date -ne $Hoje.Date) { continue }
        $c = Get-Content $arquivo -Raw -Encoding UTF8
        if ($c -match '^\s*(\w+)\|(\w+)\|') { return ($matches[2] -eq 'OK') }
    }
    return $false
}

# ---------------------------------------------------------------------
# Status de um ciclo agendado do DataSync (10:30/14:30/16:30), a partir
# do LastRunTime/LastTaskResult do Task Scheduler. Usado pra avisar o
# usuario se o painel ja reflete um sync do dia ou ainda esta desatualizado.
# ---------------------------------------------------------------------
function Get-StatusCiclo {
    param(
        [string]$Nome,
        $UltimaExecucao,
        $UltimoResultado,
        [datetime]$Hoje = (Get-Date)
    )
    # $UltimaExecucao/$UltimoResultado ficam sem tipo forte de propósito: um parametro
    # [Nullable[datetime]] eh desembrulhado pelo PowerShell ao vincular um valor nao-nulo,
    # perdendo .HasValue/.Value — mais simples tratar $null "na unha".
    if (-not $UltimaExecucao -or ([datetime]$UltimaExecucao).Date -ne $Hoje.Date) {
        return [pscustomobject]@{ Nome=$Nome; Classe='pendente'; Texto="$Nome ainda não rodou hoje" }
    }
    $hora = ([datetime]$UltimaExecucao).ToString('HH:mm')
    if ($UltimoResultado -eq 0) {
        return [pscustomobject]@{ Nome=$Nome; Classe='ok'; Texto="$Nome concluído às $hora" }
    }
    return [pscustomobject]@{ Nome=$Nome; Classe='erro'; Texto="$Nome falhou às $hora (código $UltimoResultado)" }
}

# ---------------------------------------------------------------------
# Gera o painel HTML.
# ---------------------------------------------------------------------
function New-RelatorioHtml {
    param([object[]]$Resultados, [string]$Periodo, [string]$Timestamp, [object[]]$Ciclos = @())
    $cont = @{ OK=0; PENDENTE=0; DIVERGENTE=0; ATENCAO=0; SEM_MOVIMENTO=0; ERRO=0 }
    foreach ($r in $Resultados) { $cont[$r.Status]++ }
    $totalLoja = ($Resultados | Measure-Object TicketsLoja -Sum).Sum
    $totalReta = ($Resultados | Measure-Object TicketsRetaguarda -Sum).Sum

    # Rótulos exibidos na tela (acentuados) — a chave interna ($r.Status) fica sem acento
    # de propósito, pois também vira nome de classe CSS e chave de dicionário.
    $rotulos = @{
        OK = 'OK'; PENDENTE = 'PENDENTE'; DIVERGENTE = 'DIVERGENTE'
        ATENCAO = 'ATENÇÃO'; SEM_MOVIMENTO = 'SEM MOVIMENTO'; ERRO = 'ERRO'
    }

    $linhas = foreach ($r in $Resultados) {
        $cls = $r.Status.ToLower()
        $sync = if ($r.SyncConcluido) { 'sim' } else { 'não' }
        "<tr class='$cls'><td>$($r.Loja)</td><td>$($r.TicketsLoja)</td><td>$($r.TicketsRetaguarda)</td><td>$($r.Diferenca)</td><td>$sync</td><td><span class='badge $cls'>$($rotulos[$r.Status])</span></td></tr>"
    }

    @"
<!doctype html><html lang='pt-br'><head><meta charset='utf-8'>
<meta http-equiv='refresh' content='300'><title>Verificador de Tickets — Dorinho's</title>
<style>
:root{
  --navy:#0033A0; --navy-dark:#022266; --red:#CE2B37; --gold:#FFD700;
  --bg:#f2f4f8; --card:#ffffff; --text:#1c2430; --muted:#6b7686;
}
*{box-sizing:border-box}
body{font-family:'Segoe UI',Arial,sans-serif;margin:0;background:var(--bg);color:var(--text)}
.topbar{background:linear-gradient(135deg,var(--navy) 0%,var(--navy-dark) 100%);color:#fff;
  padding:22px 32px;border-bottom:4px solid var(--gold);
  display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px}
.topbar h1{margin:0;font-size:21px;font-weight:600;letter-spacing:.3px}
.topbar .sub{font-size:12.5px;color:#cfd8f5;margin-top:2px}
.topbar .meta{text-align:right;font-size:12.5px;color:#cfd8f5}
.wrap{padding:24px 32px 40px}
.resumo{display:flex;gap:14px;flex-wrap:wrap;margin:0 0 26px}
.card{background:var(--card);border-radius:10px;padding:14px 20px;min-width:130px;
  box-shadow:0 2px 6px rgba(15,30,60,.08);border-top:3px solid var(--muted)}
.card .num{font-size:26px;font-weight:700;line-height:1.1}
.card .lbl{font-size:11.5px;color:var(--muted);text-transform:uppercase;letter-spacing:.5px;margin-top:2px}
.card.ok{border-top-color:#2e9e4d} .card.pendente{border-top-color:#e0b400}
.card.divergente{border-top-color:var(--red)} .card.atencao{border-top-color:#e8791a}
.card.sem_movimento{border-top-color:#9aa3b0} .card.erro{border-top-color:#b0142a}
.card.destaque{border-top-color:var(--navy);background:var(--navy);color:#fff}
.card.destaque .lbl{color:#cfd8f5}
.panel{background:var(--card);border-radius:10px;box-shadow:0 2px 6px rgba(15,30,60,.08);overflow:hidden}
table{border-collapse:collapse;width:100%}
thead th{background:var(--navy);color:#fff;font-size:12px;text-transform:uppercase;
  letter-spacing:.4px;padding:12px 10px;text-align:center;font-weight:600}
td{padding:9px 10px;border-bottom:1px solid #eef0f4;text-align:center;font-size:13.5px}
tbody tr:hover{background:#f7f9fd}
.badge{display:inline-block;padding:3px 10px;border-radius:20px;font-size:11.5px;font-weight:600;color:#fff}
.badge.ok{background:#2e9e4d} .badge.pendente{background:#c99400}
.badge.divergente{background:var(--red)} .badge.atencao{background:#e8791a}
.badge.sem_movimento{background:#8a93a0} .badge.erro{background:#b0142a}
tr.total td{font-weight:700;background:#eef1fb;border-top:2px solid var(--navy)}
.footer{margin-top:14px;font-size:11.5px;color:var(--muted);text-align:right}
.ciclos{display:flex;gap:8px;flex-wrap:wrap;align-items:center;margin:0 0 22px}
.ciclo{padding:5px 13px;border-radius:16px;font-size:12px;font-weight:600;color:#fff}
.ciclo.ok{background:#2e9e4d} .ciclo.pendente{background:#8a93a0} .ciclo.erro{background:#b0142a}
.btn-atualizar{background:var(--gold);color:var(--navy-dark);border:none;padding:8px 20px;
  border-radius:6px;font-weight:700;font-size:13px;cursor:pointer;text-decoration:none;
  display:inline-flex;align-items:center;gap:6px;white-space:nowrap}
.btn-atualizar:hover{background:#ffe14d}
</style>
<script>
function confirmarAtualizacao(ev){
  ev.preventDefault();
  var btn = ev.currentTarget;
  btn.textContent = 'Atualizando... (~1 min)';
  btn.style.pointerEvents = 'none';
  window.location.href = '/executar-verificacao-tickets';
}
</script>
</head><body>
<div class='topbar'>
  <div><h1>Verificador de Tickets</h1><div class='sub'>Rede Dorinho's — Loja × Retaguarda</div></div>
  <div style='display:flex;align-items:center;gap:16px'>
    <div class='meta'>Atualizado: $Timestamp<br>Período verificado: $Periodo</div>
    <a href='/executar-verificacao-tickets' class='btn-atualizar' onclick='confirmarAtualizacao(event)'>&#8635; Atualizar agora</a>
  </div>
</div>
<div class='wrap'>
$(if ($Ciclos -and $Ciclos.Count -gt 0) {
"<div class='ciclos'>" + (($Ciclos | ForEach-Object { "<span class='ciclo $($_.Classe)'>$($_.Texto)</span>" }) -join "`n") + "</div>"
})
<div class='resumo'>
  <div class='card destaque'><div class='num'>$totalLoja</div><div class='lbl'>Total tickets loja</div></div>
  <div class='card ok'><div class='num'>$($cont.OK)</div><div class='lbl'>OK</div></div>
  <div class='card pendente'><div class='num'>$($cont.PENDENTE)</div><div class='lbl'>Pendente</div></div>
  <div class='card divergente'><div class='num'>$($cont.DIVERGENTE)</div><div class='lbl'>Divergente</div></div>
  <div class='card atencao'><div class='num'>$($cont.ATENCAO)</div><div class='lbl'>Atenção</div></div>
  <div class='card sem_movimento'><div class='num'>$($cont.SEM_MOVIMENTO)</div><div class='lbl'>Sem movimento</div></div>
  <div class='card erro'><div class='num'>$($cont.ERRO)</div><div class='lbl'>Erro</div></div>
</div>
<div class='panel'>
<table>
<thead><tr><th>Loja</th><th>Tickets Loja</th><th>Tickets Retaguarda</th><th>Diferença</th><th>Sync hoje</th><th>Status</th></tr></thead>
<tbody>
$($linhas -join "`n")
<tr class='total'><td>TOTAL GERAL</td><td>$totalLoja</td><td>$totalReta</td><td>$($totalLoja - $totalReta)</td><td></td><td></td></tr>
</tbody></table>
</div>
<div class='footer'>Atualização automática a cada 5 min</div>
</div>
</body></html>
"@
}
