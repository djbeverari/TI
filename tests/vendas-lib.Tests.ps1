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

Describe 'Get-ResumoVendas' {
    BeforeAll {
        # ValorVendaBruta e ValorCancelado sao mutuamente exclusivos por ticket na retaguarda
        # (confirmado empiricamente: nenhum ticket tem os dois > 0 - um ticket cancelado ja
        # aparece com ValorVendaBruta = 0). Por isso o faturamento usa so ValorVendaBruta.
        $vendas = @(
            [pscustomobject]@{ ValorVendaBruta = 100.0; ValorCancelado = 0.0;  QtdeTotal = 2 }
            [pscustomobject]@{ ValorVendaBruta = 200.0; ValorCancelado = 0.0;  QtdeTotal = 3 }
            [pscustomobject]@{ ValorVendaBruta = 0.0;   ValorCancelado = 85.0; QtdeTotal = 0 }
            [pscustomobject]@{ ValorVendaBruta = 50.0;  ValorCancelado = 0.0;  QtdeTotal = 1 }
        )
    }

    It 'calcula o faturamento como soma de ValorVendaBruta, ignorando ValorCancelado' {
        (Get-ResumoVendas -Vendas $vendas).Faturamento | Should -Be 350.0
    }
    It 'calcula o numero de vendas (tickets), incluindo os cancelados' {
        (Get-ResumoVendas -Vendas $vendas).NumeroVendas | Should -Be 4
    }
    It 'calcula o ticket medio sobre o faturamento' {
        (Get-ResumoVendas -Vendas $vendas).TicketMedio | Should -Be 87.5
    }
    It 'calcula itens por venda' {
        (Get-ResumoVendas -Vendas $vendas).ItensPorVenda | Should -Be 1.5
    }
    It 'retorna zeros para lista vazia, sem lançar erro' {
        $resumo = Get-ResumoVendas -Vendas @()
        $resumo.Faturamento | Should -Be 0.0
        $resumo.NumeroVendas | Should -Be 0
        $resumo.TicketMedio | Should -Be 0.0
        $resumo.ItensPorVenda | Should -Be 0.0
    }
}

Describe 'Get-EvolucaoDiaria' {
    It 'agrupa faturamento por dia do mes' {
        $vendas = @(
            [pscustomobject]@{ DataVenda = [datetime]'2026-07-01'; ValorVendaBruta = 100.0; ValorCancelado = 0.0 }
            [pscustomobject]@{ DataVenda = [datetime]'2026-07-01'; ValorVendaBruta = 50.0;  ValorCancelado = 0.0 }
            [pscustomobject]@{ DataVenda = [datetime]'2026-07-03'; ValorVendaBruta = 200.0; ValorCancelado = 0.0 }
        )
        $evolucao = Get-EvolucaoDiaria -Vendas $vendas -Ano 2026 -Mes 7 -DiasNoMes 3

        $evolucao[0].Dia | Should -Be 1
        $evolucao[0].Faturamento | Should -Be 150.0
        $evolucao[1].Dia | Should -Be 2
        $evolucao[1].Faturamento | Should -Be 0.0
        $evolucao[2].Dia | Should -Be 3
        $evolucao[2].Faturamento | Should -Be 200.0
    }
}

Describe 'Get-VendasPorDiaSemana' {
    It 'agrupa faturamento por dia da semana (0=domingo a 6=sabado)' {
        $vendas = @(
            [pscustomobject]@{ DataVenda = [datetime]'2026-07-08'; ValorVendaBruta = 100.0; ValorCancelado = 0.0 } # quarta
            [pscustomobject]@{ DataVenda = [datetime]'2026-07-15'; ValorVendaBruta = 50.0;  ValorCancelado = 0.0 } # quarta
        )
        $porDia = Get-VendasPorDiaSemana -Vendas $vendas
        ($porDia | Where-Object DiaSemana -eq 'Quarta-feira').Faturamento | Should -Be 150.0
    }
}

Describe 'Get-VendasPorHora' {
    It 'agrupa faturamento por hora do dia usando DataDigitacao' {
        $vendas = @(
            [pscustomobject]@{ DataDigitacao = [datetime]'2026-07-08 10:15:00'; ValorVendaBruta = 100.0; ValorCancelado = 0.0 }
            [pscustomobject]@{ DataDigitacao = [datetime]'2026-07-08 10:45:00'; ValorVendaBruta = 50.0;  ValorCancelado = 0.0 }
            [pscustomobject]@{ DataDigitacao = [datetime]'2026-07-08 14:00:00'; ValorVendaBruta = 30.0;  ValorCancelado = 0.0 }
        )
        $porHora = Get-VendasPorHora -Vendas $vendas
        ($porHora | Where-Object Hora -eq 10).Faturamento | Should -Be 150.0
        ($porHora | Where-Object Hora -eq 14).Faturamento | Should -Be 30.0
    }
}

Describe 'Get-RankingLojas' {
    It 'ordena lojas por faturamento decrescente com variacao vs mes anterior' {
        $atual = @(
            [pscustomobject]@{ CodigoFilial = '000012'; ValorVendaBruta = 200.0; ValorCancelado = 0.0 }
            [pscustomobject]@{ CodigoFilial = '000004'; ValorVendaBruta = 300.0; ValorCancelado = 0.0 }
        )
        $anterior = @(
            [pscustomobject]@{ CodigoFilial = '000012'; ValorVendaBruta = 100.0; ValorCancelado = 0.0 }
            [pscustomobject]@{ CodigoFilial = '000004'; ValorVendaBruta = 300.0; ValorCancelado = 0.0 }
        )
        $ranking = Get-RankingLojas -VendasAtual $atual -VendasAnterior $anterior

        $ranking[0].CodigoFilial | Should -Be '000004'
        $ranking[0].Faturamento | Should -Be 300.0
        $ranking[0].VariacaoPercentual | Should -Be 0.0
        $ranking[1].CodigoFilial | Should -Be '000012'
        $ranking[1].VariacaoPercentual | Should -Be 100.0
    }

    It 'inclui loja que so vendeu no mes atual (variacao 100%)' {
        $atual = @([pscustomobject]@{ CodigoFilial = '000995'; ValorVendaBruta = 50.0; ValorCancelado = 0.0 })
        $anterior = @()
        $ranking = Get-RankingLojas -VendasAtual $atual -VendasAnterior $anterior
        $ranking[0].VariacaoPercentual | Should -Be 100.0
    }
}

Describe 'Get-TopProdutos' {
    It 'ordena produtos por receita decrescente e limita ao TopN' {
        $itens = @(
            [pscustomobject]@{ Produto = 'A'; DescProduto = 'Produto A'; Qtde = 5; ValorTotal = 100.0 }
            [pscustomobject]@{ Produto = 'A'; DescProduto = 'Produto A'; Qtde = 2; ValorTotal = 40.0 }
            [pscustomobject]@{ Produto = 'B'; DescProduto = 'Produto B'; Qtde = 10; ValorTotal = 500.0 }
        )
        $top = Get-TopProdutos -Itens $itens -TopN 2

        $top.Count | Should -Be 2
        $top[0].Produto | Should -Be 'B'
        $top[0].Receita | Should -Be 500.0
        $top[1].Produto | Should -Be 'A'
        $top[1].Receita | Should -Be 140.0
        $top[1].Quantidade | Should -Be 7
    }
}

Describe 'Get-MixCategoria' {
    It 'calcula o percentual de faturamento por categoria' {
        $itens = @(
            [pscustomobject]@{ GrupoProduto = 'Calçados';  ValorTotal = 300.0 }
            [pscustomobject]@{ GrupoProduto = 'Vestuário'; ValorTotal = 100.0 }
            [pscustomobject]@{ GrupoProduto = 'Calçados';  ValorTotal = 100.0 }
        )
        $mix = Get-MixCategoria -Itens $itens

        ($mix | Where-Object Categoria -eq 'Calçados').PercentualFaturamento | Should -Be 80.0
        ($mix | Where-Object Categoria -eq 'Vestuário').PercentualFaturamento | Should -Be 20.0
    }
}
