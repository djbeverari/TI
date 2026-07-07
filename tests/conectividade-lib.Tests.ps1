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

Describe 'Invoke-CicloConectividade' {
    BeforeAll {
        $lojas = @(
            @{ Numero = 3; Servidor = '192.168.3.100\sqlexpress' },   # roteador vai responder
            @{ Numero = 4; Servidor = '192.168.4.101\sqlexpress' },   # roteador vai falhar
            @{ Numero = 995; Servidor = '192.168.0.10\sqlexpress'; Banco = 'Lojaonline'; RotuloLog = 'E-COMMERCE' }
        )
    }

    It 'testa roteador+máquina quando roteador responde, e marca máquina N/A quando roteador falha' {
        Mock Test-IpsParalelo {
            param($Ips, $TimeoutMs)
            $r = @{}
            foreach ($ip in $Ips) {
                $r[$ip] = [PSCustomObject]@{
                    Respondeu  = ($ip -ne '192.168.4.10')
                    LatenciaMs = if ($ip -ne '192.168.4.10') { 15 } else { $null }
                }
            }
            return $r
        }

        $linhas = Invoke-CicloConectividade -Lojas $lojas -SemRoteador @('E-COMMERCE')

        ($linhas | Where-Object { $_.Loja -eq '3' -and $_.Tipo -eq 'Roteador' }).Respondeu | Should -Be $true
        ($linhas | Where-Object { $_.Loja -eq '3' -and $_.Tipo -eq 'Maquina' }).Respondeu | Should -Be $true

        ($linhas | Where-Object { $_.Loja -eq '4' -and $_.Tipo -eq 'Roteador' }).Respondeu | Should -Be $false
        ($linhas | Where-Object { $_.Loja -eq '4' -and $_.Tipo -eq 'Maquina' }).Respondeu | Should -BeNullOrEmpty

        ($linhas | Where-Object { $_.Loja -eq 'E-COMMERCE' }).Tipo | Should -Be 'Maquina'
    }

    It 'retorna array vazio sem erro quando não há lojas' {
        Mock Test-IpsParalelo { @{} }
        $linhas = @(Invoke-CicloConectividade -Lojas @())
        $linhas.Count | Should -Be 0
    }
}

Describe 'Add-HistoricoConectividade e Get-HistoricoDia' {
    It 'grava e lê de volta as linhas do dia' {
        $logDir = Join-Path $TestDrive 'logs'
        $data = Get-Date '2026-07-07'

        $linhas1 = @(
            [PSCustomObject]@{ Timestamp = '2026-07-07T08:00:00'; Loja = '3'; Tipo = 'Roteador'; Ip = '192.168.3.10'; Respondeu = $true; LatenciaMs = 12 }
        )
        $linhas2 = @(
            [PSCustomObject]@{ Timestamp = '2026-07-07T08:05:00'; Loja = '3'; Tipo = 'Roteador'; Ip = '192.168.3.10'; Respondeu = $false; LatenciaMs = $null }
        )

        Add-HistoricoConectividade -Linhas $linhas1 -LogDir $logDir -Data $data
        Add-HistoricoConectividade -Linhas $linhas2 -LogDir $logDir -Data $data

        $historico = Get-HistoricoDia -LogDir $logDir -Data $data
        $historico.Count | Should -Be 2
        $historico[0].Loja | Should -Be '3'
    }

    It 'retorna array vazio se o arquivo do dia não existe' {
        $logDir = Join-Path $TestDrive 'logs-vazio'
        (Get-HistoricoDia -LogDir $logDir -Data (Get-Date '2026-01-01')).Count | Should -Be 0
    }

    It 'não cria arquivo nem lança erro quando Linhas está vazio' {
        $logDir = Join-Path $TestDrive 'logs-noop'
        $data = Get-Date '2026-07-07'

        { Add-HistoricoConectividade -Linhas @() -LogDir $logDir -Data $data } | Should -Not -Throw

        (Get-HistoricoDia -LogDir $logDir -Data $data).Count | Should -Be 0
    }
}

Describe 'Get-EstatisticasLoja' {
    BeforeAll {
        $historico = @(
            [PSCustomObject]@{ Timestamp = '2026-07-07T08:00:00'; Loja = '3'; Tipo = 'Maquina'; Respondeu = 'True' },
            [PSCustomObject]@{ Timestamp = '2026-07-07T08:05:00'; Loja = '3'; Tipo = 'Maquina'; Respondeu = 'False' },
            [PSCustomObject]@{ Timestamp = '2026-07-07T08:10:00'; Loja = '3'; Tipo = 'Maquina'; Respondeu = 'True' },
            [PSCustomObject]@{ Timestamp = '2026-07-07T08:10:00'; Loja = '4'; Tipo = 'Maquina'; Respondeu = '' }
        )
    }

    It 'calcula uptime% e última resposta ignorando linhas N/A' {
        $stats = Get-EstatisticasLoja -Historico $historico -Loja '3' -Tipo 'Maquina'
        $stats.UptimePct | Should -Be 67
        $stats.UltimaResposta | Should -Be '2026-07-07T08:10:00'
    }

    It 'retorna "—" e 0% quando nunca respondeu (só linhas N/A)' {
        $stats = Get-EstatisticasLoja -Historico $historico -Loja '4' -Tipo 'Maquina'
        $stats.UptimePct | Should -Be 0
        $stats.UltimaResposta | Should -Be '—'
    }

    It 'retorna "—" e 0% quando a loja não aparece no histórico' {
        $stats = Get-EstatisticasLoja -Historico $historico -Loja '99' -Tipo 'Maquina'
        $stats.UptimePct | Should -Be 0
        $stats.UltimaResposta | Should -Be '—'
    }

    It 'retorna "—" e 0% quando Historico está vazio (início do dia)' {
        $stats = Get-EstatisticasLoja -Historico @() -Loja '3' -Tipo 'Maquina'
        $stats.UptimePct | Should -Be 0
        $stats.UltimaResposta | Should -Be '—'
    }
}
