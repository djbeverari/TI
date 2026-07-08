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
