. "$PSScriptRoot\vendas-lib.ps1"
. "$PSScriptRoot\vendas-queries.ps1"

$hoje = Get-Date
$anoAtual = $hoje.Year
$mesAtual = $hoje.Month

$mesAnteriorData = $hoje.AddMonths(-1)
$anoAnterior = $mesAnteriorData.Year
$mesAnteriorNum = $mesAnteriorData.Month

$anoPassadoData = $hoje.AddYears(-1)

$vendasAtual      = Get-VendasMes -Ano $anoAtual -Mes $mesAtual
$vendasAnterior   = Get-VendasMes -Ano $anoAnterior -Mes $mesAnteriorNum
$vendasAnoPassado = Get-VendasMes -Ano $anoPassadoData.Year -Mes $anoPassadoData.Month

$itensAtual = Get-ItensVendaMes -Ano $anoAtual -Mes $mesAtual

foreach ($v in $vendasAtual)      { $v.CodigoFilial = Format-CodigoFilial $v.CodigoFilial }
foreach ($v in $vendasAnterior)   { $v.CodigoFilial = Format-CodigoFilial $v.CodigoFilial }
foreach ($v in $vendasAnoPassado) { $v.CodigoFilial = Format-CodigoFilial $v.CodigoFilial }

$resumoAtual      = Get-ResumoVendas -Vendas $vendasAtual
$resumoAnterior   = Get-ResumoVendas -Vendas $vendasAnterior
$resumoAnoPassado = Get-ResumoVendas -Vendas $vendasAnoPassado

$diasNoMesAtual = [DateTime]::DaysInMonth($anoAtual, $mesAtual)
$evolucaoAtual    = Get-EvolucaoDiaria -Vendas $vendasAtual -Ano $anoAtual -Mes $mesAtual -DiasNoMes $diasNoMesAtual
$evolucaoAnterior = Get-EvolucaoDiaria -Vendas $vendasAnterior -Ano $anoAnterior -Mes $mesAnteriorNum -DiasNoMes $diasNoMesAtual

$rankingLojas = Get-RankingLojas -VendasAtual $vendasAtual -VendasAnterior $vendasAnterior
$porDiaSemana = Get-VendasPorDiaSemana -Vendas $vendasAtual
$porHora      = Get-VendasPorHora -Vendas $vendasAtual
$topProdutos  = Get-TopProdutos -Itens $itensAtual -TopN 10
$mixCategoria = Get-MixCategoria -Itens $itensAtual

$payload = [pscustomobject]@{
    GeradoEm               = $hoje.ToString('dd/MM/yyyy HH:mm')
    ResumoAtual            = $resumoAtual
    VariacaoFaturamentoMoM = Get-VariacaoPercentual -Atual $resumoAtual.Faturamento -Anterior $resumoAnterior.Faturamento
    VariacaoFaturamentoYoY = Get-VariacaoPercentual -Atual $resumoAtual.Faturamento -Anterior $resumoAnoPassado.Faturamento
    EvolucaoAtual          = @($evolucaoAtual)
    EvolucaoAnterior       = @($evolucaoAnterior)
    RankingLojas           = @($rankingLojas)
    PorDiaSemana           = @($porDiaSemana)
    PorHora                = @($porHora)
    TopProdutos            = @($topProdutos)
    MixCategoria           = @($mixCategoria)
}

$json = $payload | ConvertTo-Json -Depth 6 -Compress

$html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8">
<title>Painel de Vendas - Rede Dorinhos</title>
<style>
  body { font-family: Segoe UI, Arial, sans-serif; margin: 20px; background: #f5f5f5; }
  .cards { display: flex; gap: 12px; margin-bottom: 20px; flex-wrap: wrap; }
  .card { flex: 1; min-width: 180px; background: white; border-radius: 8px; padding: 14px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
  .card .label { font-size: 12px; color: #888; text-transform: uppercase; }
  .card h3 { margin: 4px 0; }
  table { width: 100%; border-collapse: collapse; background: white; margin-bottom: 20px; }
  th, td { text-align: left; padding: 6px 10px; border-bottom: 1px solid #eee; }
  .up { color: #2e7d32; } .down { color: #c62828; }
  canvas { background: white; border-radius: 8px; margin-bottom: 20px; }
</style>
</head>
<body>
<h1>Painel de Vendas — Rede Dorinhos</h1>
<p id="atualizado"></p>
<div class="cards" id="cards"></div>
<h2>Ranking de Lojas</h2>
<table id="ranking"><thead><tr><th>Loja</th><th>Faturamento</th><th>Variação</th></tr></thead><tbody></tbody></table>
<h2>Top Produtos</h2>
<table id="produtos"><thead><tr><th>Produto</th><th>Qtde</th><th>Receita</th></tr></thead><tbody></tbody></table>
<h2>Mix por Categoria</h2>
<table id="categorias"><thead><tr><th>Categoria</th><th>%</th></tr></thead><tbody></tbody></table>
<h2>Evolução Diária (mês atual x mês anterior)</h2>
<canvas id="graficoEvolucao" width="900" height="200"></canvas>
<h2>Vendas por Dia da Semana</h2>
<canvas id="graficoDiaSemana" width="900" height="150"></canvas>
<h2>Horário de Pico</h2>
<canvas id="graficoHora" width="900" height="150"></canvas>
<h2>Detalhe da Loja <span id="lojaSelecionadaTitulo"></span></h2>
<div id="detalheLoja"><p>Clique numa loja no ranking acima para ver detalhe.</p></div>

<script>
const dados = $json;

document.getElementById('atualizado').textContent = 'Atualizado em: ' + dados.GeradoEm;

function variacaoHtml(v) {
    const cls = v >= 0 ? 'up' : 'down';
    const seta = v >= 0 ? '▲' : '▼';
    return '<span class="' + cls + '">' + seta + ' ' + Math.abs(v).toFixed(1) + '%</span>';
}

const cardsEl = document.getElementById('cards');
cardsEl.innerHTML = [
    '<div class="card"><div class="label">Faturamento do mês</div><h3>R$ ' + dados.ResumoAtual.Faturamento.toLocaleString('pt-BR') + '</h3>' + variacaoHtml(dados.VariacaoFaturamentoMoM) + ' MoM / ' + variacaoHtml(dados.VariacaoFaturamentoYoY) + ' YoY</div>',
    '<div class="card"><div class="label">Ticket médio</div><h3>R$ ' + dados.ResumoAtual.TicketMedio.toLocaleString('pt-BR') + '</h3></div>',
    '<div class="card"><div class="label">Nº de vendas</div><h3>' + dados.ResumoAtual.NumeroVendas.toLocaleString('pt-BR') + '</h3></div>',
    '<div class="card"><div class="label">Itens por venda</div><h3>' + dados.ResumoAtual.ItensPorVenda + '</h3></div>'
].join('');

const rankingBody = document.querySelector('#ranking tbody');
rankingBody.innerHTML = dados.RankingLojas.map(l =>
    '<tr><td>' + l.CodigoFilial + '</td><td>R$ ' + l.Faturamento.toLocaleString('pt-BR') + '</td><td>' + variacaoHtml(l.VariacaoPercentual) + '</td></tr>'
).join('');

const produtosBody = document.querySelector('#produtos tbody');
produtosBody.innerHTML = dados.TopProdutos.map(p =>
    '<tr><td>' + (p.DescProduto || p.Produto) + '</td><td>' + p.Quantidade + '</td><td>R$ ' + p.Receita.toLocaleString('pt-BR') + '</td></tr>'
).join('');

const categoriasBody = document.querySelector('#categorias tbody');
categoriasBody.innerHTML = dados.MixCategoria.map(c =>
    '<tr><td>' + c.Categoria + '</td><td>' + c.PercentualFaturamento.toFixed(1) + '%</td></tr>'
).join('');

function desenharBarras(canvasId, labels, valores, corBarra) {
    const canvas = document.getElementById(canvasId);
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const max = Math.max(...valores, 1);
    const larguraBarra = canvas.width / valores.length;
    valores.forEach((v, i) => {
        const altura = (v / max) * (canvas.height - 20);
        ctx.fillStyle = corBarra;
        ctx.fillRect(i * larguraBarra + 2, canvas.height - altura, larguraBarra - 4, altura);
    });
}

desenharBarras('graficoEvolucao', dados.EvolucaoAtual.map(d => d.Dia), dados.EvolucaoAtual.map(d => d.Faturamento), '#1e88e5');
desenharBarras('graficoDiaSemana', dados.PorDiaSemana.map(d => d.DiaSemana), dados.PorDiaSemana.map(d => d.Faturamento), '#43a047');
desenharBarras('graficoHora', dados.PorHora.map(d => d.Hora), dados.PorHora.map(d => d.Faturamento), '#fb8c00');

document.querySelectorAll('#ranking tbody tr').forEach((tr, i) => {
    tr.style.cursor = 'pointer';
    tr.addEventListener('click', () => {
        const loja = dados.RankingLojas[i];
        document.getElementById('lojaSelecionadaTitulo').textContent = loja.CodigoFilial;
        document.getElementById('detalheLoja').innerHTML =
            '<p>Faturamento: R$ ' + loja.Faturamento.toLocaleString('pt-BR') + '</p>' +
            '<p>Variação vs mês anterior: ' + variacaoHtml(loja.VariacaoPercentual) + '</p>';
    });
});
</script>
</body>
</html>
"@

$pastaDestino = "C:\Logs\DataSync"
if (-not (Test-Path $pastaDestino)) {
    New-Item -ItemType Directory -Path $pastaDestino -Force | Out-Null
}
$destino = Join-Path $pastaDestino "vendas.html"
$html | Out-File -FilePath $destino -Encoding UTF8
Write-Host "Painel gerado em $destino" -ForegroundColor Green
