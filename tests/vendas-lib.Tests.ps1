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
