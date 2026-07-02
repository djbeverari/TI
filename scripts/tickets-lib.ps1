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
# Gera o painel HTML.
# ---------------------------------------------------------------------
function New-RelatorioHtml {
    param([object[]]$Resultados, [string]$Periodo, [string]$Timestamp)
    $cont = @{ OK=0; PENDENTE=0; DIVERGENTE=0; ATENCAO=0; SEM_MOVIMENTO=0; ERRO=0 }
    foreach ($r in $Resultados) { $cont[$r.Status]++ }
    $totalLoja = ($Resultados | Measure-Object TicketsLoja -Sum).Sum
    $totalReta = ($Resultados | Measure-Object TicketsRetaguarda -Sum).Sum

    $linhas = foreach ($r in $Resultados) {
        $cls = $r.Status.ToLower()
        $sync = if ($r.SyncConcluido) { 'sim' } else { 'não' }
        "<tr class='$cls'><td>$($r.Loja)</td><td>$($r.TicketsLoja)</td><td>$($r.TicketsRetaguarda)</td><td>$($r.Diferenca)</td><td>$sync</td><td>$($r.Status)</td></tr>"
    }

    @"
<!doctype html><html lang='pt-br'><head><meta charset='utf-8'>
<meta http-equiv='refresh' content='300'><title>Verificador de Tickets</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:20px;background:#f4f6f8}
h1{font-size:20px} .resumo{display:flex;gap:16px;flex-wrap:wrap;margin:16px 0}
.card{background:#fff;border-radius:8px;padding:12px 18px;box-shadow:0 1px 3px rgba(0,0,0,.1)}
table{border-collapse:collapse;width:100%;background:#fff}
th,td{padding:8px 10px;border-bottom:1px solid #eee;text-align:center}
tr.ok{background:#e7f6e7} tr.pendente{background:#fff6d6} tr.divergente{background:#fbdcdc}
tr.atencao{background:#ffe6cc} tr.sem_movimento{background:#f0f0f0} tr.erro{background:#ffe0b3}
tr.total{font-weight:bold;background:#eef}
</style></head><body>
<h1>Verificador de Tickets — Rede Dorinho's</h1>
<div>Atualizado: $Timestamp &nbsp;|&nbsp; Período verificado: $Periodo</div>
<div class='resumo'>
  <div class='card'>OK: $($cont.OK)</div>
  <div class='card'>PENDENTE: $($cont.PENDENTE)</div>
  <div class='card'>DIVERGENTE: $($cont.DIVERGENTE)</div>
  <div class='card'>ATENÇÃO: $($cont.ATENCAO)</div>
  <div class='card'>SEM MOVIMENTO: $($cont.SEM_MOVIMENTO)</div>
  <div class='card'>ERRO: $($cont.ERRO)</div>
  <div class='card'>Total tickets loja: $totalLoja</div>
</div>
<table>
<thead><tr><th>Loja</th><th>Tickets Loja</th><th>Tickets Retaguarda</th><th>Diferença</th><th>Sync hoje</th><th>Status</th></tr></thead>
<tbody>
$($linhas -join "`n")
<tr class='total'><td>TOTAL GERAL</td><td>$totalLoja</td><td>$totalReta</td><td>$($totalLoja - $totalReta)</td><td></td><td></td></tr>
</tbody></table>
</body></html>
"@
}
