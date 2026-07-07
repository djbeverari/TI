BeforeAll {
    . "$PSScriptRoot\..\conectividade-lib.ps1"
}

Describe 'Get-RouterIp' {
    It 'troca o último octeto por 10' {
        Get-RouterIp -MachineIp '192.168.47.100' | Should -Be '192.168.47.10'
    }

    It 'funciona com IP de dois dígitos no último octeto' {
        Get-RouterIp -MachineIp '192.168.5.99' | Should -Be '192.168.5.10'
    }

    It 'lança erro para IP com formato inválido' {
        { Get-RouterIp -MachineIp '192.168.47' } | Should -Throw
    }
}

Describe 'Get-LojaIp' {
    It 'extrai o host de "IP\sqlexpress"' {
        Get-LojaIp -Servidor '192.168.47.100\sqlexpress' | Should -Be '192.168.47.100'
    }

    It 'retorna o próprio IP se não houver instância' {
        Get-LojaIp -Servidor '192.168.0.10' | Should -Be '192.168.0.10'
    }
}

Describe 'Get-LojaRotulo' {
    It 'usa RotuloLog quando presente' {
        Get-LojaRotulo -Loja @{ Numero = 995; RotuloLog = 'E-COMMERCE' } | Should -Be 'E-COMMERCE'
    }

    It 'usa Numero como string quando não há RotuloLog' {
        Get-LojaRotulo -Loja @{ Numero = 3 } | Should -Be '3'
    }
}

Describe 'Get-LojasParaTeste' {
    BeforeAll {
        $lojas = @(
            @{ Numero = 3; Servidor = '192.168.3.100\sqlexpress' },
            @{ Numero = 4; Servidor = '192.168.4.101\sqlexpress' },
            @{ Numero = 995; Servidor = '192.168.0.10\sqlexpress'; Banco = 'Lojaonline'; RotuloLog = 'E-COMMERCE' }
        )
    }

    It 'gera Roteador + Maquina para loja normal' {
        $alvos = Get-LojasParaTeste -Lojas $lojas -SemRoteador @('E-COMMERCE')
        $daLoja3 = @($alvos | Where-Object { $_.Loja -eq '3' })
        $daLoja3.Count | Should -Be 2
        ($daLoja3 | Where-Object Tipo -eq 'Roteador').Ip | Should -Be '192.168.3.10'
        ($daLoja3 | Where-Object Tipo -eq 'Maquina').Ip | Should -Be '192.168.3.100'
    }

    It 'gera só Maquina para lojas em SemRoteador (identificadas por RotuloLog)' {
        $alvos = Get-LojasParaTeste -Lojas $lojas -SemRoteador @('E-COMMERCE')
        $doEcommerce = @($alvos | Where-Object { $_.Loja -eq 'E-COMMERCE' })
        $doEcommerce.Count | Should -Be 1
        $doEcommerce[0].Tipo | Should -Be 'Maquina'
        $doEcommerce[0].Ip | Should -Be '192.168.0.10'
    }

    It 'total de alvos é 2 por loja normal + 1 para SemRoteador' {
        $alvos = Get-LojasParaTeste -Lojas $lojas -SemRoteador @('E-COMMERCE')
        $alvos.Count | Should -Be 5
    }
}

Describe 'Test-IpsParalelo' {
    It 'reporta sucesso para localhost e falha para IP não roteável' {
        $resultados = Test-IpsParalelo -Ips @('127.0.0.1', '198.51.100.1') -TimeoutMs 1000

        $resultados['127.0.0.1'].Respondeu | Should -Be $true
        $resultados['127.0.0.1'].LatenciaMs | Should -BeGreaterOrEqual 0

        $resultados['198.51.100.1'].Respondeu | Should -Be $false
        $resultados['198.51.100.1'].LatenciaMs | Should -Be $null
    }

    It 'retorna hashtable vazia para lista vazia' {
        Test-IpsParalelo -Ips @() | Should -BeOfType [hashtable]
        (Test-IpsParalelo -Ips @()).Count | Should -Be 0
    }

    It 'não derruba o ciclo inteiro quando uma tarefa individual falha (IP malformado)' {
        $resultados = Test-IpsParalelo -Ips @('127.0.0.1', 'nao-e-um-ip-valido') -TimeoutMs 1000

        $resultados['127.0.0.1'].Respondeu | Should -Be $true
        $resultados['nao-e-um-ip-valido'].Respondeu | Should -Be $false
        $resultados['nao-e-um-ip-valido'].LatenciaMs | Should -Be $null
    }
}
