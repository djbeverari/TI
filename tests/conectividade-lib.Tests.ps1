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
