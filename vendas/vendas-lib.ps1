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
