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
    $html | Should -Match 'OK: 1'
    $html | Should -Match 'DIVERGENTE: 1'
    $html | Should -Match 'PENDENTE: 1'
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
