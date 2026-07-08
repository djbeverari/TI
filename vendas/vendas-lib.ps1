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
