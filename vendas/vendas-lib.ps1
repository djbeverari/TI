function Format-CodigoFilial {
    param([Parameter(Mandatory)]$Numero)
    "{0:D6}" -f [int]$Numero
}

function Format-DataSql {
    param([Parameter(Mandatory)][datetime]$Data)
    $Data.ToString('yyyyMMdd')
}

function Get-VariacaoPercentual {
    param(
        [Parameter(Mandatory)][double]$Atual,
        [Parameter(Mandatory)][double]$Anterior
    )
    if ($Anterior -eq 0) {
        if ($Atual -eq 0) { return 0.0 }
        return 100.0
    }
    [math]::Round((($Atual - $Anterior) / $Anterior) * 100, 2)
}

function Get-ResumoVendas {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Vendas)

    $numeroVendas = $Vendas.Count
    if ($numeroVendas -eq 0) {
        return [pscustomobject]@{
            Faturamento   = 0.0
            NumeroVendas  = 0
            TicketMedio   = 0.0
            ItensPorVenda = 0.0
        }
    }

    $faturamento = ($Vendas | ForEach-Object { $_.ValorVendaBruta - $_.ValorCancelado } | Measure-Object -Sum).Sum
    $qtdeTotal   = ($Vendas | Measure-Object -Property QtdeTotal -Sum).Sum

    [pscustomobject]@{
        Faturamento   = [math]::Round($faturamento, 2)
        NumeroVendas  = $numeroVendas
        TicketMedio   = [math]::Round($faturamento / $numeroVendas, 2)
        ItensPorVenda = [math]::Round($qtdeTotal / $numeroVendas, 2)
    }
}

function Get-EvolucaoDiaria {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$Vendas,
        [Parameter(Mandatory)][int]$Ano,
        [Parameter(Mandatory)][int]$Mes,
        [Parameter(Mandatory)][int]$DiasNoMes
    )

    $porDia = @{}
    foreach ($venda in $Vendas) {
        $dia = $venda.DataVenda.Day
        $liquido = $venda.ValorVendaBruta - $venda.ValorCancelado
        if (-not $porDia.ContainsKey($dia)) { $porDia[$dia] = 0.0 }
        $porDia[$dia] += $liquido
    }

    1..$DiasNoMes | ForEach-Object {
        $dia = $_
        [pscustomobject]@{
            Dia         = $dia
            Faturamento = if ($porDia.ContainsKey($dia)) { [math]::Round($porDia[$dia], 2) } else { 0.0 }
        }
    }
}

function Get-VendasPorDiaSemana {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Vendas)

    $nomes = @('Domingo','Segunda-feira','Terça-feira','Quarta-feira','Quinta-feira','Sexta-feira','Sábado')
    $porDia = @{}
    foreach ($venda in $Vendas) {
        $indice = [int]$venda.DataVenda.DayOfWeek
        $liquido = $venda.ValorVendaBruta - $venda.ValorCancelado
        if (-not $porDia.ContainsKey($indice)) { $porDia[$indice] = 0.0 }
        $porDia[$indice] += $liquido
    }

    0..6 | ForEach-Object {
        [pscustomobject]@{
            DiaSemana   = $nomes[$_]
            Faturamento = if ($porDia.ContainsKey($_)) { [math]::Round($porDia[$_], 2) } else { 0.0 }
        }
    }
}

function Get-VendasPorHora {
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Vendas)

    $porHora = @{}
    foreach ($venda in $Vendas) {
        $hora = $venda.DataDigitacao.Hour
        $liquido = $venda.ValorVendaBruta - $venda.ValorCancelado
        if (-not $porHora.ContainsKey($hora)) { $porHora[$hora] = 0.0 }
        $porHora[$hora] += $liquido
    }

    0..23 | ForEach-Object {
        [pscustomobject]@{
            Hora        = $_
            Faturamento = if ($porHora.ContainsKey($_)) { [math]::Round($porHora[$_], 2) } else { 0.0 }
        }
    }
}

function Get-RankingLojas {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$VendasAtual,
        [Parameter(Mandatory)][AllowEmptyCollection()][array]$VendasAnterior
    )

    function Agrupar($vendas) {
        $porLoja = @{}
        foreach ($v in $vendas) {
            $liquido = $v.ValorVendaBruta - $v.ValorCancelado
            if (-not $porLoja.ContainsKey($v.CodigoFilial)) { $porLoja[$v.CodigoFilial] = 0.0 }
            $porLoja[$v.CodigoFilial] += $liquido
        }
        $porLoja
    }

    $atualPorLoja    = Agrupar $VendasAtual
    $anteriorPorLoja = Agrupar $VendasAnterior

    $atualPorLoja.Keys | ForEach-Object {
        $codigo = $_
        $faturamentoAtual = $atualPorLoja[$codigo]
        $faturamentoAnterior = if ($anteriorPorLoja.ContainsKey($codigo)) { $anteriorPorLoja[$codigo] } else { 0.0 }
        [pscustomobject]@{
            CodigoFilial       = $codigo
            Faturamento        = [math]::Round($faturamentoAtual, 2)
            VariacaoPercentual = Get-VariacaoPercentual -Atual $faturamentoAtual -Anterior $faturamentoAnterior
        }
    } | Sort-Object Faturamento -Descending
}
