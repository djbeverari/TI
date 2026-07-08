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
                [pscustomobject]@{ loja = 7; produto = "Meia Kit 3"; codigo = "11902"; quantidade = -5; data = [datetime]"2026-07-07" }
                [pscustomobject]@{ loja = 3; produto = "Camiseta P Azul"; codigo = "10234"; quantidade = -2; data = [datetime]"2026-07-07" }
            )
        }

        $cred = New-Object System.Management.Automation.PSCredential("sa", (ConvertTo-SecureString "senha" -AsPlainText -Force))
        $result = Get-NegativosData -Server "192.168.0.55" -Database "Dorinhos_2022" -Credential $cred

        $result.Count | Should -Be 2
        $result[0].produto | Should -Be "Meia Kit 3"
        Should -Invoke Invoke-Sqlcmd -Times 1 -ParameterFilter {
            $ServerInstance -eq "192.168.0.55" -and $Database -eq "Dorinhos_2022" -and $Query -match "ORDER BY quantidade ASC"
        }
    }
}

Describe "Save-NegativosEstado / Get-NegativosEstado" {
    It "salva e recupera itens e timestamp em round-trip" {
        $path = Join-Path $TestDrive "estado.json"
        $itens = @(
            [pscustomobject]@{ loja = 3; produto = "Camiseta P Azul"; codigo = "10234"; quantidade = -2; data = [datetime]"2026-07-07" }
        )
        $geradoEm = [datetime]"2026-07-08T11:05:00"

        Save-NegativosEstado -Items $itens -GeradoEm $geradoEm -Path $path
        $estado = Get-NegativosEstado -Path $path

        $estado.Items.Count | Should -Be 1
        $estado.Items[0].produto | Should -Be "Camiseta P Azul"
        [datetime]$estado.GeradoEm | Should -Be $geradoEm
    }

    It "retorna `$null quando o arquivo de estado ainda não existe" {
        $path = Join-Path $TestDrive "nao-existe.json"
        Get-NegativosEstado -Path $path | Should -BeNullOrEmpty
    }
}

Describe "New-PainelHtml" {
    BeforeAll {
        $itensExemplo = @(
            [pscustomobject]@{ loja = 7; produto = "Meia Kit 3"; codigo = "11902"; quantidade = -5; data = [datetime]"2026-07-07" }
            [pscustomobject]@{ loja = 3; produto = "Camiseta P Azul"; codigo = "10234"; quantidade = -2; data = [datetime]"2026-07-07" }
        )
    }

    It "inclui total de itens, total de lojas distintas e cada produto na tabela" {
        $html = New-PainelHtml -Items $itensExemplo -GeradoEm ([datetime]"2026-07-08T11:05:00") -Desatualizado $false

        $html | Should -Match "Total de itens.*2"
        $html | Should -Match "Lojas afetadas.*2"
        $html | Should -Match "Meia Kit 3"
        $html | Should -Match "Camiseta P Azul"
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
}
