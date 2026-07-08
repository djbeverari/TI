Add-Type -AssemblyName System.Web

function Get-NegativosData {
    param(
        [Parameter(Mandatory)] [string]$Server,
        [Parameter(Mandatory)] [string]$Database,
        [Parameter(Mandatory)] [pscredential]$Credential
    )

    $query = "SELECT loja, produto, codigo, quantidade, data FROM estoque_negativos ORDER BY quantidade ASC"

    Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Credential $Credential -Query $query -ErrorAction Stop
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

function New-PainelHtml {
    param(
        [array]$Items = @(),
        [Parameter(Mandatory)] [datetime]$GeradoEm,
        [bool]$Desatualizado = $false
    )

    $totalItens = $Items.Count
    $lojasAfetadas = ($Items | Select-Object -ExpandProperty loja -Unique).Count

    $avisoHtml = ""
    if ($Desatualizado) {
        $avisoHtml = "<div class='aviso'>&#9888; dados desatualizados desde $($GeradoEm.ToString('dd/MM/yyyy HH:mm'))</div>"
    }

    $linhas = $Items | ForEach-Object {
        $dataStr = ([datetime]$_.data).ToString("dd/MM/yyyy")
        "<tr data-loja='$($_.loja)' data-produto='$([System.Web.HttpUtility]::HtmlEncode($_.produto).ToLower())'>" +
        "<td>$($_.loja)</td><td>$($_.produto)</td><td>$($_.codigo)</td>" +
        "<td class='qtd'>$($_.quantidade)</td><td>$dataStr</td></tr>"
    }
    $linhasHtml = ($linhas -join "`n")

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
<input id="busca" type="text" placeholder="Filtrar por loja ou produto...">
<table id="tabela">
<thead><tr><th>Loja</th><th>Produto</th><th>Código</th><th>Quantidade</th><th>Data</th></tr></thead>
<tbody>
$linhasHtml
</tbody>
</table>
<script>
document.getElementById('busca').addEventListener('input', function (e) {
  var termo = e.target.value.toLowerCase();
  document.querySelectorAll('#tabela tbody tr').forEach(function (tr) {
    var loja = tr.getAttribute('data-loja');
    var produto = tr.getAttribute('data-produto');
    tr.style.display = (loja.indexOf(termo) !== -1 || produto.indexOf(termo) !== -1) ? '' : 'none';
  });
});
</script>
</body>
</html>
"@
}
