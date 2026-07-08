. "$PSScriptRoot\conexao-retaguarda.ps1"

function Get-VendasMes {
    param(
        [Parameter(Mandatory)][int]$Ano,
        [Parameter(Mandatory)][int]$Mes
    )
    $inicio = Get-Date -Year $Ano -Month $Mes -Day 1
    $fim    = $inicio.AddMonths(1).AddDays(-1)
    $query = @"
SELECT CODIGO_FILIAL, DATA_VENDA, DATA_DIGITACAO, VALOR_VENDA_BRUTA, VALOR_CANCELADO, QTDE_TOTAL
FROM loja_venda
WHERE DATA_VENDA BETWEEN '$(Format-DataSql $inicio)' AND '$(Format-DataSql $fim)'
"@
    Invoke-QueryRetaguarda -Query $query | ForEach-Object {
        [pscustomobject]@{
            CodigoFilial    = $_.CODIGO_FILIAL
            DataVenda       = [datetime]$_.DATA_VENDA
            DataDigitacao   = [datetime]$_.DATA_DIGITACAO
            ValorVendaBruta = [double]$_.VALOR_VENDA_BRUTA
            ValorCancelado  = [double]$_.VALOR_CANCELADO
            QtdeTotal       = [int]$_.QTDE_TOTAL
        }
    }
}

function Get-ItensVendaMes {
    param(
        [Parameter(Mandatory)][int]$Ano,
        [Parameter(Mandatory)][int]$Mes
    )
    $inicio = Get-Date -Year $Ano -Month $Mes -Day 1
    $fim    = $inicio.AddMonths(1).AddDays(-1)
    $query = @"
SELECT vp.PRODUTO, p.DESC_PRODUTO, p.GRUPO_PRODUTO, vp.QTDE, vp.VALOR_TOTAL
FROM loja_venda_produto vp
LEFT JOIN PRODUTOS p ON p.PRODUTO = vp.PRODUTO
WHERE vp.DATA_VENDA BETWEEN '$(Format-DataSql $inicio)' AND '$(Format-DataSql $fim)'
  AND vp.ITEM_EXCLUIDO = 0
  AND vp.ITEM_NOTA_DEV = 0
"@
    Invoke-QueryRetaguarda -Query $query | ForEach-Object {
        [pscustomobject]@{
            Produto      = $_.PRODUTO
            DescProduto  = $_.DESC_PRODUTO
            GrupoProduto = $_.GRUPO_PRODUTO
            Qtde         = [int]$_.QTDE
            ValorTotal   = [double]$_.VALOR_TOTAL
        }
    }
}
