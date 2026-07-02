# Verificador de Tickets Diário — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Script PowerShell agendado que compara diariamente a contagem de tickets (`loja_venda`) de cada uma das 38 lojas com o banco consolidado da retaguarda (Dorinhos, 192.168.0.55) e publica um painel HTML alertando divergências.

**Architecture:** Um script orquestrador (`verifica-tickets.ps1`) que dot-sourceia uma biblioteca de funções puras e testáveis (`tickets-lib.ps1`) e um arquivo de config com os IPs (`lojas-config.ps1`). A lógica pura (classificação de status, cálculo de datas com feriados, geração de HTML) é coberta por testes Pester. As partes de I/O (SQL, Brasil API, status do datasync) são funções finas verificadas por integração/dry-run. O HTML gerado é servido pelo `http.server` Python já existente do datasync.

**Tech Stack:** Windows PowerShell 5.1, `System.Data.SqlClient` (ADO.NET, sem módulo extra), Pester 5 (testes), Brasil API (feriados), Task Scheduler, Python http.server (já em produção).

---

## File Structure

| Arquivo | Responsabilidade |
|---|---|
| `scripts/lojas-config.ps1` | **(já existe)** IPs das 38 lojas, retaguarda, usuário sa, caminho do `.sql_cred`. Preenchido nesta rodada. |
| `scripts/tickets-lib.ps1` | Funções puras e de I/O: `Get-TicketStatus`, `Get-DatasParaVerificar`, `Get-Feriados`, `Get-TicketCount`, `Get-SyncConcluidoLoja`, `New-RelatorioHtml`, `Write-VerificaLog`. |
| `scripts/verifica-tickets.ps1` | Orquestrador: carrega config, resolve datas/feriados, consulta lojas+retaguarda, classifica, gera HTML, loga. |
| `scripts/guardar-senha-sql.ps1` | Grava a senha do `sa` protegida por DPAPI em `C:\Users\Daniella\ti\.sql_cred`. |
| `tests/tickets-lib.Tests.ps1` | Testes Pester da lógica pura (status, datas, HTML). |
| `feriados_municipais.csv` | Feriados municipais por loja (mantido à mão). |

Convenção de nomes de status usada em TODO o projeto (string exata):
`OK`, `PENDENTE`, `DIVERGENTE`, `ATENCAO`, `SEM_MOVIMENTO`, `ERRO`.

---

## Task 0: Setup e credencial do sa

**Files:**
- Create: `scripts/guardar-senha-sql.ps1`
- Verify: Pester 5 disponível

- [ ] **Step 1: Verificar Pester**

Run: `powershell -Command "Get-Module -ListAvailable Pester | Select-Object Version"`
Expected: uma versão 5.x listada. Se não houver, rode `Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck`.

- [ ] **Step 2: Criar o script que guarda as senhas do sa (DPAPI)**

As 38 lojas compartilham uma senha; a retaguarda tem outra. Grava as duas.

```powershell
# scripts/guardar-senha-sql.ps1
# Grava as senhas do 'sa' protegidas por DPAPI (só o usuário atual descriptografa).
$lojas = Read-Host -AsSecureString "Senha do sa das LOJAS (compartilhada)"
($lojas | ConvertFrom-SecureString) | Set-Content "C:\Users\Daniella\ti\.sql_cred" -Encoding ASCII

$reta = Read-Host -AsSecureString "Senha do sa da RETAGUARDA (Dorinhos)"
($reta | ConvertFrom-SecureString) | Set-Content "C:\Users\Daniella\ti\.sql_cred_retaguarda" -Encoding ASCII

Write-Host "Senhas gravadas (.sql_cred e .sql_cred_retaguarda)"
```

- [ ] **Step 3: Rodar e gravar as senhas**

Run: `powershell -ExecutionPolicy Bypass -File scripts/guardar-senha-sql.ps1`
Expected: digita as duas senhas; arquivos criados. (Confirmar: `Test-Path C:\Users\Daniella\ti\.sql_cred` e `.sql_cred_retaguarda` → True.)

- [ ] **Step 4: Commit**

```bash
git add scripts/guardar-senha-sql.ps1
git commit -m "feat: script para guardar senha do sa via DPAPI"
```

---

## Task 1: Confirmar nomes de banco e coluna (recon)

Preenche os 3 placeholders do `lojas-config.ps1` com valores reais. Usa o [recon SQL](../../../scripts/recon-ips-lojas.sql).

**Files:**
- Modify: `scripts/lojas-config.ps1` (trocar `<BANCO_LINX_LOJA>`, `<BANCO_RETAGUARDA>`, `<coluna_loja>`)

- [ ] **Step 1: Descobrir o banco da retaguarda**

No SSMS conectado em `192.168.0.55`, rode:
```sql
SELECT name FROM sys.databases WHERE database_id > 4 ORDER BY name;
```
Anote o banco consolidado do Linx (ex.: algo como `LinxRetaguarda`, `Dorinhos`, etc.).

- [ ] **Step 2: Descobrir o banco Linx de uma loja**

No SSMS conectado numa loja qualquer (ex.: `192.168.11.100\sqlexpress`, loja 03), rode a mesma query e anote o banco local.

- [ ] **Step 3: Confirmar tabela/coluna de tickets e coluna de loja**

No banco da retaguarda, rode (do recon SQL, passo 4):
```sql
SELECT c.name AS coluna, ty.name AS tipo
FROM sys.columns c
JOIN sys.tables  t  ON t.object_id = c.object_id
JOIN sys.types   ty ON ty.user_type_id = c.user_type_id
WHERE t.name = 'loja_venda'
  AND (c.name LIKE '%loja%' OR c.name LIKE '%filial%' OR c.name LIKE '%empresa%');
```
Anote o nome exato da coluna de loja. Se a tabela não se chamar `loja_venda`, anote o nome real (e ajuste o spec/lib).

- [ ] **Step 4: Preencher o config**

Editar `scripts/lojas-config.ps1`:
```powershell
$BancoLoja = "NOME_REAL_LOJA"            # do Step 2
$BancoRetaguarda = "NOME_REAL_RETAGUARDA" # do Step 1
$ColunaLojaRetaguarda = "coluna_real"     # do Step 3
```

- [ ] **Step 5: Validar a conexão numa loja (smoke test)**

```powershell
. .\scripts\lojas-config.ps1
$sec = Get-Content $SqlCredFile | ConvertTo-SecureString
$pw  = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
$cs  = "Server=192.168.11.100\sqlexpress;Database=$BancoLoja;User Id=$SqlUser;Password=$pw;Connect Timeout=15"
$cn  = New-Object System.Data.SqlClient.SqlConnection $cs
$cn.Open(); Write-Host "Conectou:" $cn.State; $cn.Close()
```
Expected: `Conectou: Open`. Se falhar, revisar `$BancoLoja`/senha/firewall antes de seguir.

- [ ] **Step 6: Commit**

```bash
git add scripts/lojas-config.ps1
git commit -m "config: preenche nomes de banco e coluna de loja (recon)"
```

---

## Task 2: Get-TicketStatus (classificação — TDD)

Função pura que decide o status de uma loja. Núcleo da regra pendente vs divergente.

**Files:**
- Create: `scripts/tickets-lib.ps1`
- Test: `tests/tickets-lib.Tests.ps1`

- [ ] **Step 1: Escrever os testes que falham**

```powershell
# tests/tickets-lib.Tests.ps1
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
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `powershell -Command "Invoke-Pester tests/tickets-lib.Tests.ps1 -Output Detailed"`
Expected: FAIL — `Get-TicketStatus` não reconhecido.

- [ ] **Step 3: Implementar Get-TicketStatus**

```powershell
# scripts/tickets-lib.ps1
function Get-TicketStatus {
    param(
        [int]$TicketsLoja,
        [int]$TicketsRetaguarda,
        [bool]$SyncConcluido,
        [bool]$ErroConexao
    )
    if ($ErroConexao) { return 'ERRO' }
    if ($TicketsLoja -eq 0 -and $TicketsRetaguarda -eq 0) { return 'SEM_MOVIMENTO' }
    if ($TicketsRetaguarda -eq $TicketsLoja) { return 'OK' }
    if ($TicketsRetaguarda -gt $TicketsLoja) { return 'ATENCAO' }
    if ($SyncConcluido) { return 'DIVERGENTE' } else { return 'PENDENTE' }
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: `powershell -Command "Invoke-Pester tests/tickets-lib.Tests.ps1 -Output Detailed"`
Expected: PASS (6/6).

- [ ] **Step 5: Commit**

```bash
git add scripts/tickets-lib.ps1 tests/tickets-lib.Tests.ps1
git commit -m "feat: Get-TicketStatus com regra pendente vs divergente"
```

---

## Task 3: Get-DatasParaVerificar (datas + feriados — TDD)

Função pura: dado o dia de referência e a lista de feriados, retorna as datas a verificar.

**Files:**
- Modify: `scripts/tickets-lib.ps1`
- Modify: `tests/tickets-lib.Tests.ps1`

- [ ] **Step 1: Escrever os testes que falham**

Regra: parte do último dia útil antes da referência (inclusive) até o dia anterior à referência (inclusive). Dias úteis = não sábado/domingo e não feriado.

```powershell
Describe 'Get-DatasParaVerificar' {
  It 'dia normal: so o dia anterior' {
    # Terca 2026-07-07 -> verifica segunda 2026-07-06
    $r = Get-DatasParaVerificar -Referencia ([datetime]'2026-07-07') -Feriados @()
    $r | Should -HaveCount 1
    $r[0].ToString('yyyy-MM-dd') | Should -Be '2026-07-06'
  }
  It 'segunda-feira: sexta+sabado+domingo' {
    # Segunda 2026-07-06 -> sexta 03, sab 04, dom 05
    $r = Get-DatasParaVerificar -Referencia ([datetime]'2026-07-06') -Feriados @()
    ($r | ForEach-Object { $_.ToString('yyyy-MM-dd') }) | Should -Be @('2026-07-03','2026-07-04','2026-07-05')
  }
  It 'apos feriado na quinta: quarta+quinta' {
    # Sexta 2026-07-10, feriado quinta 2026-07-09 -> quarta 08 + quinta 09
    $r = Get-DatasParaVerificar -Referencia ([datetime]'2026-07-10') -Feriados @([datetime]'2026-07-09')
    ($r | ForEach-Object { $_.ToString('yyyy-MM-dd') }) | Should -Be @('2026-07-08','2026-07-09')
  }
}
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `powershell -Command "Invoke-Pester tests/tickets-lib.Tests.ps1 -Output Detailed"`
Expected: FAIL — `Get-DatasParaVerificar` não reconhecido.

- [ ] **Step 3: Implementar**

```powershell
function Test-DiaUtil {
    param([datetime]$Data, [datetime[]]$Feriados)
    if ($Data.DayOfWeek -eq 'Saturday' -or $Data.DayOfWeek -eq 'Sunday') { return $false }
    foreach ($f in $Feriados) { if ($f.Date -eq $Data.Date) { return $false } }
    return $true
}

function Get-DatasParaVerificar {
    param([datetime]$Referencia, [datetime[]]$Feriados = @())
    # Ultimo dia util antes da referencia
    $prev = $Referencia.Date.AddDays(-1)
    while (-not (Test-DiaUtil -Data $prev -Feriados $Feriados)) { $prev = $prev.AddDays(-1) }
    # Todas as datas de $prev ate o dia anterior a referencia (inclusive)
    $datas = @()
    $d = $prev
    while ($d -lt $Referencia.Date) { $datas += $d; $d = $d.AddDays(1) }
    return ,$datas
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: `powershell -Command "Invoke-Pester tests/tickets-lib.Tests.ps1 -Output Detailed"`
Expected: PASS (todos).

- [ ] **Step 5: Commit**

```bash
git add scripts/tickets-lib.ps1 tests/tickets-lib.Tests.ps1
git commit -m "feat: Get-DatasParaVerificar com regra de fim de semana e feriado"
```

---

## Task 4: Get-Feriados (Brasil API + cache + municipal)

Função de I/O com fallback. Testada por caminho de cache (sem rede).

**Files:**
- Modify: `scripts/tickets-lib.ps1`
- Modify: `tests/tickets-lib.Tests.ps1`
- Create (em produção): `feriados_municipais.csv`

- [ ] **Step 1: Teste do parser municipal (puro, sem rede)**

```powershell
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
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `powershell -Command "Invoke-Pester tests/tickets-lib.Tests.ps1 -Output Detailed"`
Expected: FAIL — `Get-FeriadosMunicipais` não reconhecido.

- [ ] **Step 3: Implementar parser municipal + feriados nacionais com cache**

```powershell
function Get-FeriadosMunicipais {
    param([string]$Csv, [int]$Loja)
    if (-not (Test-Path $Csv)) { return @() }
    $datas = @()
    foreach ($linha in Import-Csv -Path $Csv) {
        $lojas = $linha.LOJAS
        $vale = ($lojas -eq 'TODAS') -or (($lojas -split '\|') -contains "$Loja")
        if ($vale) { $datas += [datetime]::ParseExact($linha.DATA, 'yyyy-MM-dd', $null) }
    }
    return ,$datas
}

function Get-FeriadosNacionais {
    param([int]$Ano, [string]$CacheFile)
    # Cache anual: se ja tem o ano, usa cache
    if (Test-Path $CacheFile) {
        $cache = Get-Content $CacheFile -Raw | ConvertFrom-Json
        if ($cache.$Ano) { return @($cache.$Ano | ForEach-Object { [datetime]$_ }) }
    } else { $cache = [ordered]@{} }
    try {
        $resp = Invoke-RestMethod -Uri "https://brasilapi.com.br/api/feriados/v1/$Ano" -TimeoutSec 20
        $datas = $resp | ForEach-Object { $_.date }
        $cache | Add-Member -NotePropertyName "$Ano" -NotePropertyValue $datas -Force
        $cache | ConvertTo-Json | Set-Content $CacheFile -Encoding UTF8
        return @($datas | ForEach-Object { [datetime]$_ })
    } catch {
        # Fallback: feriados nacionais fixos (sem Corpus Christi/Carnaval, que sao moveis)
        return @(
            [datetime]"$Ano-01-01", [datetime]"$Ano-04-21", [datetime]"$Ano-05-01",
            [datetime]"$Ano-09-07", [datetime]"$Ano-10-12", [datetime]"$Ano-11-02",
            [datetime]"$Ano-11-15", [datetime]"$Ano-12-25"
        )
    }
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: `powershell -Command "Invoke-Pester tests/tickets-lib.Tests.ps1 -Output Detailed"`
Expected: PASS.

- [ ] **Step 5: Criar o CSV municipal inicial (produção)**

```csv
DATA,DESCRICAO,LOJAS
```
(cabeçalho só; a Daniella preenche os feriados municipais reais depois.)

- [ ] **Step 6: Commit**

```bash
git add scripts/tickets-lib.ps1 tests/tickets-lib.Tests.ps1 feriados_municipais.csv
git commit -m "feat: feriados nacionais (Brasil API + cache) e municipais por loja"
```

---

## Task 5: Get-TicketCount e Get-SyncConcluidoLoja (I/O)

Funções finas de acesso a dados. Verificadas por integração (não Pester).

**Files:**
- Modify: `scripts/tickets-lib.ps1`

- [ ] **Step 1: Implementar Get-TicketCount (ADO.NET)**

```powershell
function Get-TicketCount {
    param(
        [string]$Servidor, [string]$Banco, [string]$Usuario, [string]$Senha,
        [datetime[]]$Datas, [string]$ColunaLoja, [int]$Loja, [int]$TimeoutSec = 20
    )
    $inList = ($Datas | ForEach-Object { "'" + $_.ToString('yyyy-MM-dd') + "'" }) -join ','
    $where = "data_venda IN ($inList)"
    if ($ColunaLoja) { $where += " AND [$ColunaLoja] = $Loja" }
    $sql = "SELECT COUNT(*) FROM loja_venda WHERE $where"
    $cs  = "Server=$Servidor;Database=$Banco;User Id=$Usuario;Password=$Senha;Connect Timeout=$TimeoutSec"
    $cn  = New-Object System.Data.SqlClient.SqlConnection $cs
    try {
        $cn.Open()
        $cmd = $cn.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = $TimeoutSec
        return [int]$cmd.ExecuteScalar()
    } finally { $cn.Close() }
}
```

> Nota: quem chama envolve em try/catch. Exceção (loja offline) → status `ERRO`.

- [ ] **Step 2: Implementar Get-SyncConcluidoLoja**

Confirmar o caminho/formato do status contra `gerar-painel-datasync.ps1` (usa `loja_<numero>.txt`). Interpretação: existe status de sucesso do dia de hoje para a loja.

```powershell
function Get-SyncConcluidoLoja {
    param([int]$Loja, [string]$StatusDir, [datetime]$Hoje = (Get-Date))
    $arquivo = Join-Path $StatusDir ("loja_{0}.txt" -f $Loja)
    if (-not (Test-Path $arquivo)) { return $false }
    $conteudo = Get-Content $arquivo -Raw
    # Sucesso se o status é OK e a data do arquivo é de hoje
    $doDia = (Get-Item $arquivo).LastWriteTime.Date -eq $Hoje.Date
    return ($doDia -and $conteudo -match 'OK|SUCESSO|SUCCESS')
}
```

- [ ] **Step 3: Smoke test de contagem numa loja**

```powershell
. .\scripts\lojas-config.ps1; . .\scripts\tickets-lib.ps1
$sec = Get-Content $SqlCredFile | ConvertTo-SecureString
$pw  = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
Get-TicketCount -Servidor "192.168.11.100\sqlexpress" -Banco $BancoLoja -Usuario $SqlUser -Senha $pw `
    -Datas @([datetime]::Today.AddDays(-1)) -ColunaLoja $null -Loja 3
```
Expected: um número inteiro (contagem de ontem na loja 03). Confirma tabela/coluna reais.

- [ ] **Step 4: Commit**

```bash
git add scripts/tickets-lib.ps1
git commit -m "feat: Get-TicketCount (ADO.NET) e Get-SyncConcluidoLoja"
```

---

## Task 6: New-RelatorioHtml (painel — TDD nos marcadores)

Função pura: dado o array de resultados + metadados, retorna o HTML.

**Files:**
- Modify: `scripts/tickets-lib.ps1`
- Modify: `tests/tickets-lib.Tests.ps1`

- [ ] **Step 1: Escrever os testes que falham**

```powershell
Describe 'New-RelatorioHtml' {
  BeforeAll {
    $script:res = @(
      [pscustomobject]@{ Loja=3; TicketsLoja=10; TicketsRetaguarda=10; Diferenca=0;  SyncConcluido=$true;  Status='OK' }
      [pscustomobject]@{ Loja=4; TicketsLoja=12; TicketsRetaguarda=5;  Diferenca=7;  SyncConcluido=$true;  Status='DIVERGENTE' }
      [pscustomobject]@{ Loja=5; TicketsLoja=8;  TicketsRetaguarda=3;  Diferenca=5;  SyncConcluido=$false; Status='PENDENTE' }
    )
    $script:html = New-RelatorioHtml -Resultados $res -Periodo '2026-07-01' -Timestamp '2026-07-02 11:30'
  }
  It 'contem o resumo com contagens por status' {
    $html | Should -Match 'OK.*1'
    $html | Should -Match 'DIVERGENTE.*1'
    $html | Should -Match 'PENDENTE.*1'
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
```

- [ ] **Step 2: Rodar e ver falhar**

Run: `powershell -Command "Invoke-Pester tests/tickets-lib.Tests.ps1 -Output Detailed"`
Expected: FAIL — `New-RelatorioHtml` não reconhecido.

- [ ] **Step 3: Implementar New-RelatorioHtml**

```powershell
function New-RelatorioHtml {
    param([object[]]$Resultados, [string]$Periodo, [string]$Timestamp)
    $cont = @{ OK=0; PENDENTE=0; DIVERGENTE=0; ATENCAO=0; SEM_MOVIMENTO=0; ERRO=0 }
    foreach ($r in $Resultados) { $cont[$r.Status]++ }
    $totalLoja = ($Resultados | Measure-Object TicketsLoja -Sum).Sum
    $totalReta = ($Resultados | Measure-Object TicketsRetaguarda -Sum).Sum

    $linhas = foreach ($r in $Resultados) {
        $cls = $r.Status.ToLower()
        $sync = if ($r.SyncConcluido) { 'sim' } else { 'não' }
        "<tr class='$cls'><td>$($r.Loja)</td><td>$($r.TicketsLoja)</td><td>$($r.TicketsRetaguarda)</td><td>$($r.Diferenca)</td><td>$sync</td><td>$($r.Status)</td></tr>"
    }

    @"
<!doctype html><html lang='pt-br'><head><meta charset='utf-8'>
<meta http-equiv='refresh' content='300'><title>Verificador de Tickets</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:20px;background:#f4f6f8}
h1{font-size:20px} .resumo{display:flex;gap:16px;flex-wrap:wrap;margin:16px 0}
.card{background:#fff;border-radius:8px;padding:12px 18px;box-shadow:0 1px 3px rgba(0,0,0,.1)}
table{border-collapse:collapse;width:100%;background:#fff}
th,td{padding:8px 10px;border-bottom:1px solid #eee;text-align:center}
tr.ok{background:#e7f6e7} tr.pendente{background:#fff6d6} tr.divergente{background:#fbdcdc}
tr.atencao{background:#ffe6cc} tr.sem_movimento{background:#f0f0f0} tr.erro{background:#ffe0b3}
tr.total{font-weight:bold;background:#eef}
</style></head><body>
<h1>Verificador de Tickets — Rede Dorinho's</h1>
<div>Atualizado: $Timestamp &nbsp;|&nbsp; Período verificado: $Periodo</div>
<div class='resumo'>
  <div class='card'>OK: $($cont.OK)</div>
  <div class='card'>PENDENTE: $($cont.PENDENTE)</div>
  <div class='card'>DIVERGENTE: $($cont.DIVERGENTE)</div>
  <div class='card'>ATENÇÃO: $($cont.ATENCAO)</div>
  <div class='card'>SEM MOVIMENTO: $($cont.SEM_MOVIMENTO)</div>
  <div class='card'>ERRO: $($cont.ERRO)</div>
  <div class='card'>Total tickets loja: $totalLoja</div>
</div>
<table>
<thead><tr><th>Loja</th><th>Tickets Loja</th><th>Tickets Retaguarda</th><th>Diferença</th><th>Sync hoje</th><th>Status</th></tr></thead>
<tbody>
$($linhas -join "`n")
<tr class='total'><td>TOTAL GERAL</td><td>$totalLoja</td><td>$totalReta</td><td>$($totalLoja - $totalReta)</td><td></td><td></td></tr>
</tbody></table>
</body></html>
"@
}
```

- [ ] **Step 4: Rodar e ver passar**

Run: `powershell -Command "Invoke-Pester tests/tickets-lib.Tests.ps1 -Output Detailed"`
Expected: PASS (todos os describes).

- [ ] **Step 5: Commit**

```bash
git add scripts/tickets-lib.ps1 tests/tickets-lib.Tests.ps1
git commit -m "feat: New-RelatorioHtml com resumo, cores por status e total geral"
```

---

## Task 7: Orquestrador verifica-tickets.ps1

Junta tudo: config → datas → consultas → classificação → HTML → log.

**Files:**
- Create: `scripts/verifica-tickets.ps1`

- [ ] **Step 1: Implementar o orquestrador**

```powershell
# scripts/verifica-tickets.ps1
$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot
. (Join-Path $base 'lojas-config.ps1')
. (Join-Path $base 'tickets-lib.ps1')

$LogDir = 'C:\Logs\VerificaTickets'
$SaidaHtml = 'C:\WebRelatorios\tickets.html'
$CacheFeriados = Join-Path $base 'feriados_cache.json'
$CsvMunicipal  = Join-Path $base 'feriados_municipais.csv'
$StatusDir     = 'C:\Users\Datasync\Desktop\ti\status'   # CONFIRMAR contra o datasync
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-VerificaLog {
    param([string]$Msg, [string]$Nivel = 'INFO')
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $arq = Join-Path $LogDir ("verifica_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))
    Add-Content -Path $arq -Value "[$ts] [$Nivel] $Msg"
}

# Senhas do sa (DPAPI) — lojas e retaguarda são diferentes
function Read-SqlSenha {
    param([string]$Arquivo)
    $sec = Get-Content $Arquivo | ConvertTo-SecureString
    [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}
$pwLojas      = Read-SqlSenha $SqlCredFile
$pwRetaguarda = Read-SqlSenha $SqlCredFileRetaguarda

$hoje = Get-Date
$ano  = $hoje.Year
Write-VerificaLog "Inicio da verificacao (ref=$($hoje.ToString('yyyy-MM-dd')))"

$resultados = foreach ($loja in $Lojas) {
    $feriados = @()
    $feriados += Get-FeriadosNacionais -Ano $ano -CacheFile $CacheFeriados
    $feriados += Get-FeriadosMunicipais -Csv $CsvMunicipal -Loja $loja.Numero
    $datas = Get-DatasParaVerificar -Referencia $hoje -Feriados $feriados

    $erro = $false; $tl = 0; $tr = 0
    try {
        $tl = Get-TicketCount -Servidor $loja.Servidor -Banco $BancoLoja -Usuario $SqlUser -Senha $pwLojas `
                              -Datas $datas -ColunaLoja $null -Loja $loja.Numero
        $tr = Get-TicketCount -Servidor $Retaguarda.Servidor -Banco $BancoRetaguarda -Usuario $SqlUser -Senha $pwRetaguarda `
                              -Datas $datas -ColunaLoja $ColunaLojaRetaguarda -Loja $loja.Numero
    } catch {
        $erro = $true
        Write-VerificaLog "Loja $($loja.Numero): erro de conexao - $($_.Exception.Message)" 'ERROR'
    }
    $sync = Get-SyncConcluidoLoja -Loja $loja.Numero -StatusDir $StatusDir -Hoje $hoje
    $status = Get-TicketStatus -TicketsLoja $tl -TicketsRetaguarda $tr -SyncConcluido $sync -ErroConexao $erro

    [pscustomobject]@{
        Loja=$loja.Numero; TicketsLoja=$tl; TicketsRetaguarda=$tr;
        Diferenca=($tl - $tr); SyncConcluido=$sync; Status=$status
    }
}

$periodo = (Get-DatasParaVerificar -Referencia $hoje -Feriados @() |
            ForEach-Object { $_.ToString('dd/MM') }) -join ', '
$html = New-RelatorioHtml -Resultados $resultados -Periodo $periodo -Timestamp $hoje.ToString('yyyy-MM-dd HH:mm')
if (-not (Test-Path (Split-Path $SaidaHtml))) { New-Item -ItemType Directory -Path (Split-Path $SaidaHtml) -Force | Out-Null }
Set-Content -Path $SaidaHtml -Value $html -Encoding UTF8

$div = ($resultados | Where-Object Status -eq 'DIVERGENTE').Count
Write-VerificaLog "Fim. Divergentes=$div  Pendentes=$(($resultados|?{$_.Status -eq 'PENDENTE'}).Count)  Erros=$(($resultados|?{$_.Status -eq 'ERRO'}).Count)"
```

- [ ] **Step 2: Dry-run completo**

Run: `powershell -ExecutionPolicy Bypass -File scripts/verifica-tickets.ps1`
Expected: gera `C:\WebRelatorios\tickets.html`; log em `C:\Logs\VerificaTickets\`. Abrir o HTML no navegador e conferir as 38 linhas + resumo.

- [ ] **Step 3: Commit**

```bash
git add scripts/verifica-tickets.ps1
git commit -m "feat: orquestrador verifica-tickets.ps1 (config->consulta->html->log)"
```

---

## Task 8: Publicação e agendamento

**Files:**
- (Sem código novo — usa infra do datasync)

- [ ] **Step 1: Confirmar o serviço HTTP e a pasta servida**

O datasync já roda `DataSyncHTTP` (Python http.server na 8080). Confirmar qual pasta ele serve. Se for `C:\WebRelatorios\`, o `tickets.html` já fica acessível em `http://192.168.0.147:8080/tickets.html`. Se servir outra pasta, ajustar `$SaidaHtml` no Step 1 da Task 7 para essa pasta.

- [ ] **Step 2: Registrar a tarefa agendada (11:30, seg–sex)**

```powershell
$acao    = New-ScheduledTaskAction -Execute 'powershell.exe' `
           -Argument '-ExecutionPolicy Bypass -File C:\Users\Datasync\Desktop\ti\verifica-tickets.ps1'
$gatilho = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At 11:30
Register-ScheduledTask -TaskName 'VerificaTickets' -Action $acao -Trigger $gatilho `
    -User 'Datasync' -RunLevel Highest -Description 'Verifica tickets loja x retaguarda e gera painel'
```

- [ ] **Step 3: Rodar a tarefa manualmente e validar**

Run: `Start-ScheduledTask -TaskName 'VerificaTickets'` e depois abrir `http://192.168.0.147:8080/tickets.html`.
Expected: painel atualizado com timestamp recente.

- [ ] **Step 4: Commit da doc de deploy**

Registrar no `CHANGELOG.md`/deploy notes que a tarefa `VerificaTickets` roda 11:30 seg–sex. Commit.

---

## Task 9: Verificação final

- [ ] **Step 1: Rodar toda a suíte de testes**

Run: `powershell -Command "Invoke-Pester tests/ -Output Detailed"`
Expected: todos verdes.

- [ ] **Step 2: Conferir contra o spec**

Reler `docs/superpowers/specs/2026-05-22-verificador-tickets-design.md` e marcar que cada seção tem tarefa correspondente. Ajustar itens pendentes que foram resolvidos.

- [ ] **Step 3: Commit final**

```bash
git add -A
git commit -m "chore: verificador de tickets completo e testado"
```

---

## Notas de confirmação (pendentes de dados reais)

Estes valores precisam ser confirmados durante a execução (Tasks 1 e 5) e podem exigir pequenos ajustes na lib:
- `$BancoLoja`, `$BancoRetaguarda`, `$ColunaLojaRetaguarda` (Task 1)
- Nome real da tabela de tickets (assumido `loja_venda`) e da coluna de data (`data_venda`)
- Caminho/format real do status do datasync em `Get-SyncConcluidoLoja` (Task 5) — confirmar contra `gerar-painel-datasync.ps1`
- Pasta servida pelo `DataSyncHTTP` (Task 8)
