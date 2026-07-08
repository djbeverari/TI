# ============================================================
# Descoberta de schema: loja_venda e loja_venda_produto (retaguarda)
# ============================================================

. "$PSScriptRoot\conexao-retaguarda.ps1"

function Get-ColunasTabela {
    param([Parameter(Mandatory)][string]$NomeTabela)
    $query = @"
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = '$NomeTabela'
ORDER BY ORDINAL_POSITION
"@
    Invoke-QueryRetaguarda -Query $query
}

Write-Host "=== Colunas de loja_venda ===" -ForegroundColor Cyan
$colunas = Get-ColunasTabela -NomeTabela "loja_venda"
$colunas | Format-Table -AutoSize
$colunas | Export-Csv -Path "$PSScriptRoot\schema-loja_venda.csv" -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "=== Colunas de loja_venda_produto ===" -ForegroundColor Cyan
$colunasProduto = Get-ColunasTabela -NomeTabela "loja_venda_produto"
$colunasProduto | Format-Table -AutoSize
$colunasProduto | Export-Csv -Path "$PSScriptRoot\schema-loja_venda_produto.csv" -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "=== Tabelas candidatas (produto/categoria/departamento) ===" -ForegroundColor Cyan
$tabelasProduto = Invoke-QueryRetaguarda -Query @"
SELECT TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME LIKE '%produto%' OR TABLE_NAME LIKE '%categoria%' OR TABLE_NAME LIKE '%departamento%' OR TABLE_NAME LIKE '%grupo%'
"@
$tabelasProduto | Format-Table -AutoSize
