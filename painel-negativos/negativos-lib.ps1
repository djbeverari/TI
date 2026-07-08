Add-Type -AssemblyName System.Web

function Get-NegativosData {
    param(
        [Parameter(Mandatory)] [string]$Server,
        [Parameter(Mandatory)] [string]$Database,
        [Parameter(Mandatory)] [pscredential]$Credential
    )

    $grades = 1..10
    $selects = $grades | ForEach-Object {
        "SELECT filial AS loja, produto AS codigo, $_ AS grade, es$_ AS quantidade, data_geracao AS data FROM DANIELLA_J.estoque_negativos WHERE es$_ < 0 AND data_geracao = (SELECT MAX(data_geracao) FROM DANIELLA_J.estoque_negativos)"
    }
    $query = ($selects -join "`nUNION ALL`n") + "`nORDER BY quantidade ASC"

    Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Credential $Credential -Query $query -TrustServerCertificate -ErrorAction Stop
}

function Save-NegativosEstado {
    param(
        [Parameter(Mandatory)] [array]$Items,
        [Parameter(Mandatory)] [datetime]$GeradoEm,
        [Parameter(Mandatory)] [string]$Path
    )

    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $estado = [pscustomobject]@{
        GeradoEm = $GeradoEm.ToString("o")
        Items    = $Items
    }
    $estado | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
}

function Get-NegativosEstado {
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    Get-Content -Path $Path -Raw | ConvertFrom-Json
}

function Get-Ranking {
    param(
        [array]$Items = @(),
        [Parameter(Mandatory)] [string]$Chave
    )

    if (-not $Items -or $Items.Count -eq 0) {
        return @()
    }

    $Items | Group-Object -Property $Chave | ForEach-Object {
        [pscustomobject]@{
            Chave = $_.Name
            Soma  = ($_.Group | Measure-Object -Property quantidade -Sum).Sum
        }
    } | Sort-Object Soma
}

function ConvertTo-BarrasHtml {
    param(
        [array]$Ranking = @()
    )

    if (-not $Ranking -or $Ranking.Count -eq 0) {
        return "<p class='vazio'>Sem itens negativos.</p>"
    }

    $top = $Ranking | Select-Object -First 10
    $maxAbs = ($top | ForEach-Object { [math]::Abs($_.Soma) } | Measure-Object -Maximum).Maximum
    if (-not $maxAbs -or $maxAbs -eq 0) { $maxAbs = 1 }

    $linhas = $top | ForEach-Object {
        $pct = [math]::Round(([math]::Abs($_.Soma) / $maxAbs) * 100)
        $label = [System.Web.HttpUtility]::HtmlEncode([string]$_.Chave)
        "<div class='barra-linha'><span class='barra-label'>$label</span><div class='barra-fundo'><div class='barra' style='width:${pct}%'></div></div><span class='barra-valor'>$($_.Soma)</span></div>"
    }
    ($linhas -join "`n")
}

function New-PainelHtml {
    param(
        [array]$Items = @(),
        [Parameter(Mandatory)] [datetime]$GeradoEm,
        [bool]$Desatualizado = $false
    )

    $itensLimpos = $Items | ForEach-Object {
        [pscustomobject]@{
            loja       = ([string]$_.loja).Trim()
            codigo     = ([string]$_.codigo).Trim()
            grade      = $_.grade
            quantidade = $_.quantidade
            data       = $_.data
        }
    }

    $totalItens = $itensLimpos.Count
    $lojasAfetadas = ($itensLimpos | Select-Object -ExpandProperty loja -Unique).Count

    $avisoHtml = ""
    if ($Desatualizado) {
        $avisoHtml = "<div class='aviso'>&#9888; dados desatualizados desde $($GeradoEm.ToString('dd/MM/yyyy HH:mm'))</div>"
    }

    $linhas = $itensLimpos | ForEach-Object {
        $dataStr = ([datetime]$_.data).ToString("dd/MM/yyyy")
        "<tr data-loja='$([System.Web.HttpUtility]::HtmlEncode($_.loja).ToLower())' data-codigo='$([System.Web.HttpUtility]::HtmlEncode($_.codigo).ToLower())'>" +
        "<td>$($_.loja)</td><td>$($_.codigo)</td><td>$($_.grade)</td>" +
        "<td class='qtd'>$($_.quantidade)</td><td>$dataStr</td></tr>"
    }
    $linhasHtml = ($linhas -join "`n")

    $barrasLojasHtml = ConvertTo-BarrasHtml -Ranking (Get-Ranking -Items $itensLimpos -Chave "loja")
    $barrasProdutosHtml = ConvertTo-BarrasHtml -Ranking (Get-Ranking -Items $itensLimpos -Chave "codigo")

    @"
<!DOCTYPE html>
<html lang="pt-br">
<head>
<meta charset="utf-8">
<title>Painel de Estoque Negativos</title>
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 20px; background: #f4f4f4; }
.resumo { display: flex; gap: 16px; margin-bottom: 12px; }
.resumo div { background: white; padding: 10px 16px; border-radius: 6px; box-shadow: 0 1px 3px rgba(0,0,0,0.15); }
.aviso { background: #fff3cd; color: #856404; padding: 10px; border-radius: 6px; margin-bottom: 12px; font-weight: bold; }
.rankings { display: flex; gap: 16px; margin-bottom: 16px; flex-wrap: wrap; }
.ranking-box { background: white; padding: 12px 16px; border-radius: 6px; box-shadow: 0 1px 3px rgba(0,0,0,0.15); flex: 1; min-width: 300px; }
.ranking-box h2 { margin: 0 0 10px 0; font-size: 15px; }
.barra-linha { display: flex; align-items: center; gap: 8px; margin-bottom: 6px; font-size: 13px; }
.barra-label { width: 40%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.barra-fundo { flex: 1; background: #eee; border-radius: 3px; height: 14px; overflow: hidden; }
.barra { background: #c0392b; height: 100%; }
.barra-valor { width: 40px; text-align: right; color: #c0392b; font-weight: bold; }
.vazio { color: #777; font-size: 13px; }
input#busca { width: 100%; padding: 8px; margin-bottom: 12px; box-sizing: border-box; }
table { width: 100%; border-collapse: collapse; background: white; }
th, td { padding: 8px; border-bottom: 1px solid #ddd; text-align: left; }
td.qtd { color: #c0392b; font-weight: bold; text-align: right; }
th { background: #333; color: white; }
</style>
</head>
<body>
<h1>Painel de Estoque Negativos</h1>
<p>Gerado em: $($GeradoEm.ToString('dd/MM/yyyy HH:mm'))</p>
$avisoHtml
<div class="resumo">
<div>Total de itens: <b>$totalItens</b></div>
<div>Lojas afetadas: <b>$lojasAfetadas</b></div>
</div>
<div class="rankings">
<div class="ranking-box">
<h2>Ranking de lojas (soma da quantidade negativa)</h2>
$barrasLojasHtml
</div>
<div class="ranking-box">
<h2>Ranking de produtos (soma da quantidade negativa)</h2>
$barrasProdutosHtml
</div>
</div>
<input id="busca" type="text" placeholder="Filtrar por loja ou código do produto...">
<table id="tabela">
<thead><tr><th>Loja</th><th>Código</th><th title="Posição na grade de tamanhos do produto (não é o tamanho literal)">Grade (posição)</th><th>Quantidade</th><th>Data</th></tr></thead>
<tbody>
$linhasHtml
</tbody>
</table>
<script>
document.getElementById('busca').addEventListener('input', function (e) {
  var termo = e.target.value.toLowerCase();
  document.querySelectorAll('#tabela tbody tr').forEach(function (tr) {
    var loja = tr.getAttribute('data-loja');
    var codigo = tr.getAttribute('data-codigo');
    tr.style.display = (loja.indexOf(termo) !== -1 || codigo.indexOf(termo) !== -1) ? '' : 'none';
  });
});
</script>
</body>
</html>
"@
}
