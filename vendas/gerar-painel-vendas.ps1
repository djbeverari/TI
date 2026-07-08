. "$PSScriptRoot\vendas-lib.ps1"
. "$PSScriptRoot\vendas-queries.ps1"

$hoje = Get-Date
$anoAtual = $hoje.Year
$mesAtual = $hoje.Month
$diaAtual = $hoje.Day

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

# Comparacoes MoM/YoY usam "mesmo periodo" (dia 1 ate o dia de hoje) para nao comparar
# um mes em andamento contra um mes anterior inteiro - isso gerava uma "queda" artificial
# de quase 80% so porque o mes atual tinha poucos dias decorridos.
$vendasAnteriorMesmoPeriodo   = @($vendasAnterior   | Where-Object { $_.DataVenda.Day -le $diaAtual })
$vendasAnoPassadoMesmoPeriodo = @($vendasAnoPassado | Where-Object { $_.DataVenda.Day -le $diaAtual })

$resumoAtual      = Get-ResumoVendas -Vendas $vendasAtual
$resumoAnterior   = Get-ResumoVendas -Vendas $vendasAnteriorMesmoPeriodo
$resumoAnoPassado = Get-ResumoVendas -Vendas $vendasAnoPassadoMesmoPeriodo

$diasNoMesAtual = [DateTime]::DaysInMonth($anoAtual, $mesAtual)
$evolucaoAtual    = Get-EvolucaoDiaria -Vendas $vendasAtual -Ano $anoAtual -Mes $mesAtual -DiasNoMes $diasNoMesAtual
$evolucaoAnterior = Get-EvolucaoDiaria -Vendas $vendasAnterior -Ano $anoAnterior -Mes $mesAnteriorNum -DiasNoMes $diasNoMesAtual

$rankingLojas = Get-RankingLojas -VendasAtual $vendasAtual -VendasAnterior $vendasAnteriorMesmoPeriodo
$porDiaSemana = Get-VendasPorDiaSemana -Vendas $vendasAtual
$porHora      = Get-VendasPorHora -Vendas $vendasAtual
$topProdutos  = Get-TopProdutos -Itens $itensAtual -TopN 10
$mixCategoria = Get-MixCategoria -Itens $itensAtual

$nomesMes = @('','janeiro','fevereiro','março','abril','maio','junho','julho','agosto','setembro','outubro','novembro','dezembro')
$periodoAtualTexto      = "01/{0:D2}/{1} a {2:D2}/{0:D2}/{1}" -f $mesAtual, $anoAtual, $diaAtual
$periodoAnteriorTexto   = "01 a {0:D2} de {1}/{2}" -f $diaAtual, $nomesMes[$mesAnteriorNum], $anoAnterior
$periodoAnoPassadoTexto = "01 a {0:D2} de {1}/{2}" -f $diaAtual, $nomesMes[$mesAtual], $anoPassadoData.Year

$payload = [pscustomobject]@{
    GeradoEm               = $hoje.ToString('dd/MM/yyyy HH:mm')
    DiaAtual               = $diaAtual
    DiasNoMesAtual          = $diasNoMesAtual
    PeriodoAtualTexto       = $periodoAtualTexto
    PeriodoAnteriorTexto    = $periodoAnteriorTexto
    PeriodoAnoPassadoTexto  = $periodoAnoPassadoTexto
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
  .periodo { background: #fff8e1; border: 1px solid #ffe082; border-radius: 6px; padding: 10px 14px; margin-bottom: 16px; font-size: 13px; color: #6d4c00; }
  .cards { display: flex; gap: 12px; margin-bottom: 20px; flex-wrap: wrap; }
  .card { flex: 1; min-width: 180px; background: white; border-radius: 8px; padding: 14px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
  .card .label { font-size: 12px; color: #888; text-transform: uppercase; }
  .card h3 { margin: 4px 0; }
  .card .comparacao { font-size: 12px; display: block; margin-top: 2px; }
  table { width: 100%; border-collapse: collapse; background: white; margin-bottom: 20px; }
  th, td { text-align: left; padding: 6px 10px; border-bottom: 1px solid #eee; }
  .up { color: #2e7d32; } .down { color: #c62828; }
  canvas { background: white; border-radius: 8px; }
  .legenda { display: flex; gap: 16px; margin: 6px 0 14px 0; font-size: 12px; color: #555; }
  .legenda span { display: inline-flex; align-items: center; gap: 5px; }
  .swatch { width: 12px; height: 12px; border-radius: 2px; display: inline-block; }
  #detalheLoja { background: white; border-radius: 8px; padding: 14px; margin-bottom: 20px; min-height: 20px; }
</style>
</head>
<body>
<h1>Painel de Vendas — Rede Dorinhos</h1>
<p id="atualizado"></p>
<div class="periodo" id="periodo"></div>
<div class="cards" id="cards"></div>
<h2>Ranking de Lojas</h2>
<p class="legenda">Clique numa loja para ver o detalhe abaixo.</p>
<table id="ranking"><thead><tr><th>Loja</th><th>Faturamento</th><th>Variação vs mês anterior (mesmo período)</th></tr></thead><tbody></tbody></table>
<h2>Detalhe da Loja <span id="lojaSelecionadaTitulo"></span></h2>
<div id="detalheLoja"><p>Clique numa loja no ranking acima para ver o detalhe.</p></div>
<h2>Top Produtos</h2>
<table id="produtos"><thead><tr><th>Produto</th><th>Qtde</th><th>Receita</th></tr></thead><tbody></tbody></table>
<h2>Mix por Categoria</h2>
<table id="categorias"><thead><tr><th>Categoria</th><th>%</th></tr></thead><tbody></tbody></table>
<h2>Evolução Diária (mês atual x mês anterior, dia a dia)</h2>
<div class="legenda">
  <span><span class="swatch" style="background:#1e88e5"></span>Mês atual</span>
  <span><span class="swatch" style="background:#bbbbbb"></span>Mês anterior</span>
</div>
<canvas id="graficoEvolucao" width="900" height="220"></canvas>
<h2>Vendas por Dia da Semana</h2>
<canvas id="graficoDiaSemana" width="900" height="170"></canvas>
<h2>Horário de Pico</h2>
<canvas id="graficoHora" width="900" height="170"></canvas>

<script>
const dados = $json;

document.getElementById('atualizado').textContent = 'Atualizado em: ' + dados.GeradoEm;
document.getElementById('periodo').innerHTML =
    '<b>Período do mês atual:</b> ' + dados.PeriodoAtualTexto + ' (dia ' + dados.DiaAtual + ' de ' + dados.DiasNoMesAtual + ') &nbsp;|&nbsp; ' +
    '<b>Comparado com "mês anterior":</b> ' + dados.PeriodoAnteriorTexto + ' &nbsp;|&nbsp; ' +
    '<b>Comparado com "ano passado":</b> ' + dados.PeriodoAnoPassadoTexto +
    '<br>As comparações usam o mesmo número de dias em cada período, para não comparar um mês incompleto com um mês inteiro.';

function variacaoHtml(v) {
    const cls = v >= 0 ? 'up' : 'down';
    const seta = v >= 0 ? '▲' : '▼';
    return '<span class="' + cls + '">' + seta + ' ' + Math.abs(v).toFixed(1) + '%</span>';
}

const cardsEl = document.getElementById('cards');
cardsEl.innerHTML = [
    '<div class="card"><div class="label">Faturamento do mês (até hoje)</div><h3>R$ ' + dados.ResumoAtual.Faturamento.toLocaleString('pt-BR') + '</h3>' +
        '<span class="comparacao">' + variacaoHtml(dados.VariacaoFaturamentoMoM) + ' vs mês anterior (mesmo período)</span>' +
        '<span class="comparacao">' + variacaoHtml(dados.VariacaoFaturamentoYoY) + ' vs mesmo período ano passado</span></div>',
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

function formatarMoedaCurta(v) {
    if (Math.abs(v) >= 1000) { return 'R$ ' + (v/1000).toFixed(1) + 'mil'; }
    return 'R$ ' + v.toFixed(0);
}

function desenharBarras(canvasId, labels, valores, corBarra, maxLabels) {
    const canvas = document.getElementById(canvasId);
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const margemInferior = 26;
    const margemSuperior = 18;
    const areaUtil = canvas.height - margemInferior - margemSuperior;
    const max = Math.max(...valores, 1);

    ctx.fillStyle = '#333';
    ctx.font = '11px sans-serif';
    ctx.textAlign = 'left';
    ctx.fillText('Máx: ' + formatarMoedaCurta(max), 4, 12);

    ctx.strokeStyle = '#ddd';
    ctx.beginPath();
    ctx.moveTo(0, canvas.height - margemInferior);
    ctx.lineTo(canvas.width, canvas.height - margemInferior);
    ctx.stroke();

    const larguraBarra = canvas.width / valores.length;
    valores.forEach((v, i) => {
        const altura = (v / max) * areaUtil;
        ctx.fillStyle = corBarra;
        ctx.fillRect(i * larguraBarra + 2, canvas.height - margemInferior - altura, larguraBarra - 4, altura);
    });

    const passo = Math.max(1, Math.ceil(labels.length / (maxLabels || 15)));
    ctx.fillStyle = '#666';
    ctx.font = '10px sans-serif';
    ctx.textAlign = 'center';
    labels.forEach((lab, i) => {
        if (i % passo === 0) {
            ctx.fillText(String(lab), i * larguraBarra + larguraBarra / 2, canvas.height - 8);
        }
    });
}

function desenharLinhasComparativas(canvasId, labelsX, serieAtual, serieAnterior, diaAtual) {
    const canvas = document.getElementById(canvasId);
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    const margemInferior = 26;
    const margemSuperior = 18;
    const areaUtil = canvas.height - margemInferior - margemSuperior;
    const max = Math.max(...serieAtual, ...serieAnterior, 1);
    const passoX = canvas.width / (labelsX.length - 1 || 1);

    ctx.fillStyle = '#333';
    ctx.font = '11px sans-serif';
    ctx.textAlign = 'left';
    ctx.fillText('Máx: ' + formatarMoedaCurta(max), 4, 12);

    ctx.strokeStyle = '#ddd';
    ctx.beginPath();
    ctx.moveTo(0, canvas.height - margemInferior);
    ctx.lineTo(canvas.width, canvas.height - margemInferior);
    ctx.stroke();

    function linha(serie, cor, tracejado) {
        ctx.beginPath();
        ctx.strokeStyle = cor;
        ctx.lineWidth = 2;
        ctx.setLineDash(tracejado ? [5, 4] : []);
        serie.forEach((v, i) => {
            const x = i * passoX;
            const y = canvas.height - margemInferior - (v / max) * areaUtil;
            if (i === 0) { ctx.moveTo(x, y); } else { ctx.lineTo(x, y); }
        });
        ctx.stroke();
        ctx.setLineDash([]);
    }
    linha(serieAnterior, '#bbbbbb', true);
    linha(serieAtual, '#1e88e5', false);

    if (diaAtual && diaAtual > 0 && diaAtual <= labelsX.length) {
        const xHoje = (diaAtual - 1) * passoX;
        ctx.strokeStyle = '#e53935';
        ctx.setLineDash([3, 3]);
        ctx.beginPath();
        ctx.moveTo(xHoje, margemSuperior);
        ctx.lineTo(xHoje, canvas.height - margemInferior);
        ctx.stroke();
        ctx.setLineDash([]);
        ctx.fillStyle = '#e53935';
        ctx.font = '10px sans-serif';
        ctx.textAlign = 'center';
        ctx.fillText('hoje', xHoje, margemSuperior - 4);
    }

    const passoLabel = Math.max(1, Math.ceil(labelsX.length / 15));
    ctx.fillStyle = '#666';
    ctx.font = '10px sans-serif';
    ctx.textAlign = 'center';
    labelsX.forEach((lab, i) => {
        if (i % passoLabel === 0) {
            ctx.fillText(String(lab), i * passoX, canvas.height - 8);
        }
    });
}

desenharLinhasComparativas(
    'graficoEvolucao',
    dados.EvolucaoAtual.map(d => d.Dia),
    dados.EvolucaoAtual.map(d => d.Faturamento),
    dados.EvolucaoAnterior.map(d => d.Faturamento),
    dados.DiaAtual
);
desenharBarras('graficoDiaSemana', dados.PorDiaSemana.map(d => d.DiaSemana.substring(0,3)), dados.PorDiaSemana.map(d => d.Faturamento), '#43a047', 7);
desenharBarras('graficoHora', dados.PorHora.map(d => d.Hora + 'h'), dados.PorHora.map(d => d.Faturamento), '#fb8c00', 12);

document.querySelectorAll('#ranking tbody tr').forEach((tr, i) => {
    tr.style.cursor = 'pointer';
    tr.addEventListener('click', () => {
        const loja = dados.RankingLojas[i];
        document.getElementById('lojaSelecionadaTitulo').textContent = loja.CodigoFilial;
        document.getElementById('detalheLoja').innerHTML =
            '<p>Faturamento (' + dados.PeriodoAtualTexto + '): R$ ' + loja.Faturamento.toLocaleString('pt-BR') + '</p>' +
            '<p>Variação vs mês anterior (mesmo período): ' + variacaoHtml(loja.VariacaoPercentual) + '</p>';
        document.getElementById('detalheLoja').scrollIntoView({ behavior: 'smooth', block: 'center' });
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
