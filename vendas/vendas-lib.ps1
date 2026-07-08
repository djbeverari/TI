function Format-CodigoFilial {
    param([Parameter(Mandatory)]$Numero)
    "{0:D6}" -f [int]$Numero
}

function Format-DataSql {
    param([Parameter(Mandatory)][datetime]$Data)
    $Data.ToString('yyyyMMdd')
}
