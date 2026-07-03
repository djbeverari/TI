# Testes Pester da lógica pura do Verificador de Tickets.
# Rodar: Invoke-Pester tests/tickets-lib.Tests.ps1 -Output Detailed
BeforeAll { . "$PSScriptRoot/../scripts/tickets-lib.ps1" }

Describe 'Get-TicketStatus' {
  It 'OK quando iguais e com movimento' {
    Get-TicketStatus -TicketsLoja 10 -TicketsRetaguarda 10 -SyncConcluido $true -ErroConexao $false | Should -Be 'OK'
  }
  It 'SEM_MOVIMENTO quando ambos zero' {
    Get-TicketStatus -TicketsLoja 0 -TicketsRetaguarda 0 -SyncConcluido $true -ErroConexao $false | Should -Be 'SEM_MOVIMENTO'
  }
  It 'PENDENTE quando retaguarda menor e sync NAO concluido' {
    Get-TicketStatus -TicketsLoja 10 -TicketsRetaguarda 4 -SyncConcluido $false -ErroConexao $false | Should -Be 'PENDENTE'
  }
  It 'DIVERGENTE quando retaguarda menor e sync concluido' {
    Get-TicketStatus -TicketsLoja 10 -TicketsRetaguarda 4 -SyncConcluido $true -ErroConexao $false | Should -Be 'DIVERGENTE'
  }
  It 'ATENCAO quando retaguarda maior que a loja' {
    Get-TicketStatus -TicketsLoja 5 -TicketsRetaguarda 8 -SyncConcluido $true -ErroConexao $false | Should -Be 'ATENCAO'
  }
  It 'ERRO tem prioridade sobre tudo' {
    Get-TicketStatus -TicketsLoja 0 -TicketsRetaguarda 0 -SyncConcluido $true -ErroConexao $true | Should -Be 'ERRO'
  }
}

Describe 'Get-DatasParaVerificar' {
  It 'dia normal: so o dia anterior' {
    $r = Get-DatasParaVerificar -Referencia ([datetime]'2026-07-07') -Feriados @()
    $r | Should -HaveCount 1
    $r[0].ToString('yyyy-MM-dd') | Should -Be '2026-07-06'
  }
  It 'segunda-feira: sexta+sabado+domingo' {
    $r = Get-DatasParaVerificar -Referencia ([datetime]'2026-07-06') -Feriados @()
    ($r | ForEach-Object { $_.ToString('yyyy-MM-dd') }) | Should -Be @('2026-07-03','2026-07-04','2026-07-05')
  }
  It 'apos feriado na quinta: quarta+quinta' {
    $r = Get-DatasParaVerificar -Referencia ([datetime]'2026-07-10') -Feriados @([datetime]'2026-07-09')
    ($r | ForEach-Object { $_.ToString('yyyy-MM-dd') }) | Should -Be @('2026-07-08','2026-07-09')
  }
}

Describe 'Get-FeriadosMunicipais' {
  It 'filtra feriado da loja e TODAS' {
    $csv = @'
DATA,DESCRICAO,LOJAS
2026-06-13,Santo Antonio,3|4|5
2026-07-26,Santana,TODAS
'@
    $tmp = New-TemporaryFile
    Set-Content -Path $tmp -Value $csv -Encoding UTF8
    (Get-FeriadosMunicipais -Csv $tmp -Loja 4 | ForEach-Object { $_.ToString('yyyy-MM-dd') }) |
        Should -Be @('2026-06-13','2026-07-26')
    (Get-FeriadosMunicipais -Csv $tmp -Loja 9 | ForEach-Object { $_.ToString('yyyy-MM-dd') }) |
        Should -Be @('2026-07-26')
    Remove-Item $tmp
  }
}

Describe 'Get-SyncConcluidoLoja' {
  BeforeAll {
    $script:dir = Join-Path ([IO.Path]::GetTempPath()) ("sync_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir | Out-Null
    $script:hoje = Get-Date
    $arqHoje = Join-Path $dir ("sync_{0}.log" -f $hoje.ToString('yyyy-MM-dd'))
    @"
[2026-07-03 10:30:03] [INFO] Loja 03: Executando RECEBE...
[2026-07-03 10:31:20] [SUCCESS] [OK] Loja 03 - RECEBE concluido com sucesso
[2026-07-03 10:30:04] [INFO] Loja 31: Executando RECEBE...
[2026-07-03 10:30:05] [ERROR] [ERRO] Loja 31 - RECEBE nao concluido
[2026-07-03 14:30:04] [SUCCESS] [OK] Loja 09 - RECEBE ja concluido hoje (sync anterior)
[2026-07-03 15:12:28] [ERROR] [ERRO] Loja 04 - ENVIA: Transferencia nao concluida
[2026-07-03 10:31:20] [SUCCESS] [OK] Loja 04 - RECEBE concluido com sucesso
"@ | Set-Content $arqHoje -Encoding UTF8
  }
  AfterAll { Remove-Item $dir -Recurse -Force }

  It 'concluido quando o log de hoje tem sucesso do RECEBE' {
    Get-SyncConcluidoLoja -Loja 3 -LogDir $dir -Hoje $hoje | Should -BeTrue
  }
  It 'nao concluido quando RECEBE deu erro' {
    Get-SyncConcluidoLoja -Loja 31 -LogDir $dir -Hoje $hoje | Should -BeFalse
  }
  It 'acha loja com zero a esquerda no log (Loja 09)' {
    Get-SyncConcluidoLoja -Loja 9 -LogDir $dir -Hoje $hoje | Should -BeTrue
  }
  It 'nao concluido quando arquivo de log nao existe' {
    Get-SyncConcluidoLoja -Loja 99 -LogDir $dir -Hoje $hoje | Should -BeFalse
  }
  It 'nao concluido quando so existe log de outro dia' {
    Get-SyncConcluidoLoja -Loja 3 -LogDir $dir -Hoje $hoje.AddDays(1) | Should -BeFalse
  }
  It 'concluido pelo RECEBE mesmo com ENVIA falhando depois no mesmo dia (Loja 04)' {
    Get-SyncConcluidoLoja -Loja 4 -LogDir $dir -Hoje $hoje | Should -BeTrue
  }
}

Describe 'Get-StatusCiclo' {
  It 'ok quando rodou hoje com resultado 0' {
    $r = Get-StatusCiclo -Nome 'DataSync 10:30' -UltimaExecucao ([datetime]'2026-07-03 10:31') -UltimoResultado 0 -Hoje ([datetime]'2026-07-03 11:30')
    $r.Classe | Should -Be 'ok'
    $r.Texto | Should -Match 'concluído às 10:31'
  }
  It 'pendente quando ainda nao rodou hoje (ultima execucao e de outro dia)' {
    $r = Get-StatusCiclo -Nome 'DataSync 10:30' -UltimaExecucao ([datetime]'2026-07-02 10:31') -UltimoResultado 0 -Hoje ([datetime]'2026-07-03 09:00')
    $r.Classe | Should -Be 'pendente'
    $r.Texto | Should -Match 'ainda não rodou hoje'
  }
  It 'pendente quando nunca rodou (sem ultima execucao)' {
    $r = Get-StatusCiclo -Nome 'DataSync 10:30' -UltimaExecucao $null -UltimoResultado $null -Hoje ([datetime]'2026-07-03 09:00')
    $r.Classe | Should -Be 'pendente'
  }
  It 'pendente (nao erro) quando ainda esta rodando - codigo 267009' {
    $r = Get-StatusCiclo -Nome 'DataSync 10:30' -UltimaExecucao ([datetime]'2026-07-03 10:30') -UltimoResultado 267009 -Hoje ([datetime]'2026-07-03 11:30')
    $r.Classe | Should -Be 'pendente'
    $r.Texto | Should -Match 'ainda está rodando'
  }
  It 'erro quando rodou hoje mas resultado diferente de 0' {
    $r = Get-StatusCiclo -Nome 'DataSync 10:30' -UltimaExecucao ([datetime]'2026-07-03 10:31') -UltimoResultado 1 -Hoje ([datetime]'2026-07-03 11:30')
    $r.Classe | Should -Be 'erro'
    $r.Texto | Should -Match 'falhou'
  }
}

Describe 'New-RelatorioHtml' {
  BeforeAll {
    $script:res = @(
      [pscustomobject]@{ Loja=3; TicketsLoja=10; TicketsRetaguarda=10; Diferenca=0; SyncConcluido=$true;  Status='OK' }
      [pscustomobject]@{ Loja=4; TicketsLoja=12; TicketsRetaguarda=5;  Diferenca=7; SyncConcluido=$true;  Status='DIVERGENTE' }
      [pscustomobject]@{ Loja=5; TicketsLoja=8;  TicketsRetaguarda=3;  Diferenca=5; SyncConcluido=$false; Status='PENDENTE' }
    )
    $script:html = New-RelatorioHtml -Resultados $res -Periodo '2026-07-01' -Timestamp '2026-07-02 11:30'
  }
  It 'contem o resumo com contagens por status' {
    $html | Should -Match "(?s)card ok'>.*?'num'>1<"
    $html | Should -Match "(?s)card divergente'>.*?'num'>1<"
    $html | Should -Match "(?s)card pendente'>.*?'num'>1<"
  }
  It 'contem uma linha por loja' {
    $html | Should -Match '>3<'; $html | Should -Match '>4<'; $html | Should -Match '>5<'
  }
  It 'marca a classe css de cada status' {
    $html | Should -Match "class='divergente'"
    $html | Should -Match "class='pendente'"
  }
  It 'tem linha de total geral' {
    $html | Should -Match 'TOTAL GERAL'
  }
}
