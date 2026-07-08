BeforeAll {
    . "$PSScriptRoot\..\vendas\vendas-lib.ps1"
}

Describe 'Format-CodigoFilial' {
    It 'preenche com zero à esquerda até 6 dígitos' {
        Format-CodigoFilial -Numero 995 | Should -Be '000995'
    }
    It 'funciona com número de 1 dígito' {
        Format-CodigoFilial -Numero 3 | Should -Be '000003'
    }
    It 'aceita string numérica' {
        Format-CodigoFilial -Numero '14' | Should -Be '000014'
    }
}

Describe 'Format-DataSql' {
    It 'formata como yyyyMMdd sem separador' {
        Format-DataSql -Data (Get-Date -Year 2026 -Month 7 -Day 8) | Should -Be '20260708'
    }
    It 'preenche mês e dia com zero à esquerda' {
        Format-DataSql -Data (Get-Date -Year 2026 -Month 1 -Day 5) | Should -Be '20260105'
    }
}

Describe 'Get-VariacaoPercentual' {
    It 'calcula variação positiva' {
        Get-VariacaoPercentual -Atual 110 -Anterior 100 | Should -Be 10.0
    }
    It 'calcula variação negativa' {
        Get-VariacaoPercentual -Atual 90 -Anterior 100 | Should -Be (-10.0)
    }
    It 'retorna 0 quando anterior é 0 e atual também é 0' {
        Get-VariacaoPercentual -Atual 0 -Anterior 0 | Should -Be 0.0
    }
    It 'retorna 100 quando anterior é 0 e atual é maior que 0' {
        Get-VariacaoPercentual -Atual 50 -Anterior 0 | Should -Be 100.0
    }
}
