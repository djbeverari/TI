BeforeAll {
    if (-not (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue)) {
        # Stub para maquinas de desenvolvimento sem o modulo SqlServer instalado.
        # Na maquina de producao (com o modulo SqlServer), o cmdlet real e usado normalmente.
        function Invoke-Sqlcmd {
            param($ServerInstance, $Database, $Credential, $Query)
        }
    }

    . "$PSScriptRoot\negativos-lib.ps1"
}

Describe "Get-NegativosData" {
    It "retorna os itens ordenados por quantidade (mais negativo primeiro), vindos do Invoke-Sqlcmd" {
        Mock Invoke-Sqlcmd {
            @(
                [pscustomobject]@{ loja = "LOJA 07"; codigo = "11902"; grade = 6; quantidade = -5; data = [datetime]"2026-07-07" }
                [pscustomobject]@{ loja = "LOJA 03"; codigo = "10234"; grade = 2; quantidade = -2; data = [datetime]"2026-07-07" }
            )
        }

        $cred = New-Object System.Management.Automation.PSCredential("sa", (ConvertTo-SecureString "senha" -AsPlainText -Force))
        $result = Get-NegativosData -Server "192.168.0.55" -Database "Dorinhos_2022" -Credential $cred

        $result.Count | Should -Be 2
        $result[0].codigo | Should -Be "11902"
        Should -Invoke Invoke-Sqlcmd -Times 1 -ParameterFilter {
            $ServerInstance -eq "192.168.0.55" -and $Database -eq "Dorinhos_2022" `
                -and $Query -match "DANIELLA_J.estoque_negativos" `
                -and $Query -match "es1 < 0" -and $Query -match "es10 < 0" `
                -and $Query -match "data_geracao = \(SELECT MAX\(data_geracao\)" `
                -and $Query -match "ORDER BY quantidade ASC"
        }
    }
}

Describe "Save-NegativosEstado / Get-NegativosEstado" {
    It "salva e recupera itens e timestamp em round-trip" {
        $path = Join-Path $TestDrive "estado.json"
        $itens = @(
            [pscustomobject]@{ loja = "LOJA 03"; codigo = "10234"; grade = 2; quantidade = -2; data = [datetime]"2026-07-07" }
        )
        $geradoEm = [datetime]"2026-07-08T11:05:00"

        Save-NegativosEstado -Items $itens -GeradoEm $geradoEm -Path $path
        $estado = Get-NegativosEstado -Path $path

        $estado.Items.Count | Should -Be 1
        $estado.Items[0].codigo | Should -Be "10234"
        [datetime]$estado.GeradoEm | Should -Be $geradoEm
    }

    It "retorna `$null quando o arquivo de estado ainda não existe" {
        $path = Join-Path $TestDrive "nao-existe.json"
        Get-NegativosEstado -Path $path | Should -BeNullOrEmpty
    }
}

Describe "Get-Ranking" {
    BeforeAll {
        $itensExemplo = @(
            [pscustomobject]@{ loja = "LOJA 07"; codigo = "11902"; grade = 6; quantidade = -5; data = [datetime]"2026-07-07" }
            [pscustomobject]@{ loja = "LOJA 07"; codigo = "10234"; grade = 2; quantidade = -1; data = [datetime]"2026-07-07" }
            [pscustomobject]@{ loja = "LOJA 03"; codigo = "10234"; grade = 3; quantidade = -2; data = [datetime]"2026-07-07" }
        )
    }

    It "agrupa por loja e soma as quantidades negativas, mais severo primeiro" {
        $ranking = Get-Ranking -Items $itensExemplo -Chave "loja"

        $ranking.Count | Should -Be 2
        $ranking[0].Chave | Should -Be "LOJA 07"
        $ranking[0].Soma | Should -Be -6
        $ranking[1].Chave | Should -Be "LOJA 03"
        $ranking[1].Soma | Should -Be -2
    }

    It "agrupa por codigo e soma as quantidades negativas, mais severo primeiro" {
        $ranking = Get-Ranking -Items $itensExemplo -Chave "codigo"

        $ranking.Count | Should -Be 2
        $ranking[0].Chave | Should -Be "11902"
        $ranking[0].Soma | Should -Be -5
        $ranking[1].Chave | Should -Be "10234"
        $ranking[1].Soma | Should -Be -3
    }

    It "retorna lista vazia quando nao ha itens" {
        Get-Ranking -Items @() -Chave "loja" | Should -BeNullOrEmpty
    }
}

Describe "New-PainelHtml" {
    BeforeAll {
        $itensExemplo = @(
            [pscustomobject]@{ loja = "LOJA 07 - CENTRO   "; codigo = "11902   "; grade = 6; quantidade = -5; data = [datetime]"2026-07-07" }
            [pscustomobject]@{ loja = "LOJA 03 - SUL      "; codigo = "10234   "; grade = 2; quantidade = -2; data = [datetime]"2026-07-07" }
        )
    }

    It "inclui total de itens, total de lojas distintas, codigo e grade na tabela, sem espacos sobrando" {
        $html = New-PainelHtml -Items $itensExemplo -GeradoEm ([datetime]"2026-07-08T11:05:00") -Desatualizado $false

        $html | Should -Match "Total de itens.*2"
        $html | Should -Match "Lojas afetadas.*2"
        $html | Should -Match "<td>11902</td>"
        $html | Should -Match "<td>10234</td>"
        $html | Should -Match "<td>6</td>"
        $html | Should -Not -Match "dados desatualizados"
    }

    It "mostra o aviso de dados desatualizados quando Desatualizado for verdadeiro" {
        $html = New-PainelHtml -Items $itensExemplo -GeradoEm ([datetime]"2026-07-08T09:00:00") -Desatualizado $true

        $html | Should -Match "dados desatualizados"
    }

    It "renderiza painel vazio sem erro quando não há itens" {
        $html = New-PainelHtml -Items @() -GeradoEm ([datetime]"2026-07-08T11:05:00") -Desatualizado $false

        $html | Should -Match "Total de itens.*0"
    }

    It "inclui o ranking de lojas e de produtos por soma de quantidade negativa" {
        $html = New-PainelHtml -Items $itensExemplo -GeradoEm ([datetime]"2026-07-08T11:05:00") -Desatualizado $false

        $html | Should -Match "Ranking de lojas"
        $html | Should -Match "Ranking de produtos"
        $html | Should -Match "class='barra'"
        $html | Should -Match "LOJA 07 - CENTRO"
        $html | Should -Match "11902"
    }

    It "nao quebra o ranking quando nao ha itens" {
        $html = New-PainelHtml -Items @() -GeradoEm ([datetime]"2026-07-08T11:05:00") -Desatualizado $false

        $html | Should -Match "Ranking de lojas"
    }
}
