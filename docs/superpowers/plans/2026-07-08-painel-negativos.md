# Painel de Estoque Negativos — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir um script PowerShell agendado que consulta a tabela `estoque_negativos` na retaguarda (192.168.0.55, banco `Dorinhos_2022`) e gera um painel HTML filtrável, servido por `http.server` na máquina da Daniella.

**Architecture:** Task Scheduler roda `gera-painel-negativos.ps1` de segunda a sexta, logo após 11:00. O script chama funções de uma lib testável (`negativos-lib.ps1`) que consultam o SQL Server via `Invoke-Sqlcmd` e renderizam HTML. Em caso de falha de conexão, o script recupera o último resultado bem-sucedido de um arquivo de estado JSON e re-renderiza o painel com aviso de "dados desatualizados", nunca deixando o painel quebrado ou vazio.

**Tech Stack:** PowerShell 5.1, módulo `SqlServer` (`Invoke-Sqlcmd`), Pester (testes), Python `http.server` (hospedagem estática)

---

## Estrutura de Arquivos

```
painel-negativos/
├── negativos-lib.ps1              # Get-NegativosData, New-PainelHtml, Save-NegativosEstado, Get-NegativosEstado
├── negativos-lib.Tests.ps1        # Testes Pester das funções acima
├── gera-painel-negativos.ps1      # Script principal, chamado pelo Task Scheduler
├── salvar-credencial.ps1          # Script interativo (roda uma vez) para salvar a credencial SQL
├── instala-tarefa.ps1             # Registra a Scheduled Task de geração do painel
├── instala-servidor-web.ps1       # Registra a Scheduled Task que sobe o http.server no boot/logon
├── web/                            # Pasta servida pelo http.server (negativos.html vai aqui)
└── estado/                         # Estado persistente (negativos-estado.json), criado em runtime
```

---

## Task 1: Scaffold do projeto e função de consulta SQL

**Files:**
- Create: `painel-negativos/negativos-lib.ps1`
- Create: `painel-negativos/negativos-lib.Tests.ps1`

- [ ] **Step 1: Criar estrutura de diretórios**

```bash
mkdir -p painel-negativos/web
mkdir -p painel-negativos/estado
```

- [ ] **Step 2: Escrever o teste de `Get-NegativosData` (deve falhar)**

Criar `painel-negativos/negativos-lib.Tests.ps1`:

```powershell
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
```

- [ ] **Step 3: Rodar o teste e confirmar que falha**

Run: `Invoke-Pester painel-negativos/negativos-lib.Tests.ps1`
Expected: FAIL — `negativos-lib.ps1` não existe / `Get-NegativosData` não é reconhecido

- [ ] **Step 4: Implementar `Get-NegativosData`**

Criar `painel-negativos/negativos-lib.ps1`:

```powershell
Add-Type -AssemblyName System.Web

function Get-NegativosData {
    param(
        [Parameter(Mandatory)] [string]$Server,
        [Parameter(Mandatory)] [string]$Database,
        [Parameter(Mandatory)] [pscredential]$Credential
    )

    $query = "SELECT loja, produto, codigo, quantidade, data FROM estoque_negativos ORDER BY quantidade ASC"

    Invoke-Sqlcmd -ServerInstance $Server -Database $Database -Credential $Credential -Query $query -ErrorAction Stop
}
```

- [ ] **Step 5: Rodar o teste e confirmar que passa**

Run: `Invoke-Pester painel-negativos/negativos-lib.Tests.ps1`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add painel-negativos/negativos-lib.ps1 painel-negativos/negativos-lib.Tests.ps1
git commit -m "feat: adiciona Get-NegativosData para consultar estoque_negativos na retaguarda"
```

---

## Task 2: Persistência de estado (último resultado bem-sucedido)

**Files:**
- Modify: `painel-negativos/negativos-lib.ps1`
- Modify: `painel-negativos/negativos-lib.Tests.ps1`

- [ ] **Step 1: Escrever os testes de `Save-NegativosEstado` / `Get-NegativosEstado`**

Adicionar a `painel-negativos/negativos-lib.Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `Invoke-Pester painel-negativos/negativos-lib.Tests.ps1`
Expected: FAIL — `Save-NegativosEstado`/`Get-NegativosEstado` não reconhecidos

- [ ] **Step 3: Implementar as funções de estado**

Adicionar a `painel-negativos/negativos-lib.ps1`:

```powershell
function Save-NegativosEstado {
    param(
        [Parameter(Mandatory)] [array]$Items,
        [Parameter(Mandatory)] [datetime]$GeradoEm,
        [Parameter(Mandatory)] [string]$Path
    )

    $dir = Split-Path -Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $estado = [pscustomobject]@{
        GeradoEm = $GeradoEm.ToString("o")
        Items    = $Items
    }
    $estado | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
}

function Get-NegativosEstado {
    param(
        [Parameter(Mandatory)] [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $null
    }

    Get-Content -Path $Path -Raw | ConvertFrom-Json
}
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `Invoke-Pester painel-negativos/negativos-lib.Tests.ps1`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add painel-negativos/negativos-lib.ps1 painel-negativos/negativos-lib.Tests.ps1
git commit -m "feat: adiciona persistencia de estado para fallback de dados desatualizados"
```

---

## Task 3: Renderização do painel HTML

**Files:**
- Modify: `painel-negativos/negativos-lib.ps1`
- Modify: `painel-negativos/negativos-lib.Tests.ps1`

- [ ] **Step 1: Escrever os testes de `New-PainelHtml`**

Adicionar a `painel-negativos/negativos-lib.Tests.ps1`:

```powershell
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
```

- [ ] **Step 2: Rodar os testes e confirmar que falham**

Run: `Invoke-Pester painel-negativos/negativos-lib.Tests.ps1`
Expected: FAIL — `New-PainelHtml` não reconhecida

- [ ] **Step 3: Implementar `New-PainelHtml`**

Adicionar a `painel-negativos/negativos-lib.ps1`:

```powershell
function New-PainelHtml {
    param(
        [array]$Items = @(),
        [Parameter(Mandatory)] [datetime]$GeradoEm,
        [bool]$Desatualizado = $false
    )

    $totalItens = $Items.Count
    $lojasAfetadas = ($Items | Select-Object -ExpandProperty loja -Unique).Count

    $avisoHtml = ""
    if ($Desatualizado) {
        $avisoHtml = "<div class='aviso'>&#9888; dados desatualizados desde $($GeradoEm.ToString('dd/MM/yyyy HH:mm'))</div>"
    }

    $linhas = $Items | ForEach-Object {
        $dataStr = ([datetime]$_.data).ToString("dd/MM/yyyy")
        "<tr data-loja='$($_.loja)' data-produto='$([System.Web.HttpUtility]::HtmlEncode($_.produto).ToLower())'>" +
        "<td>$($_.loja)</td><td>$($_.produto)</td><td>$($_.codigo)</td>" +
        "<td class='qtd'>$($_.quantidade)</td><td>$dataStr</td></tr>"
    }
    $linhasHtml = ($linhas -join "`n")

    @"
<!DOCTYPE html>
<html lang="pt-br">
<head>
<meta charset="utf-8">
<title>Painel de Estoque Negativos</title>
<style>
body { font-family: Segoe UI, Arial, sans-serif; margin: 20px; background: #f4f4f4; }
.resumo { display: flex; gap: 16px; margin-bottom: 12px; }
.resumo div { background: white; padding: 10px 16px; border-radius: 6px; box-shadow: 0 1px 3px rgba(0,0,0,0.15); }
.aviso { background: #fff3cd; color: #856404; padding: 10px; border-radius: 6px; margin-bottom: 12px; font-weight: bold; }
input#busca { width: 100%; padding: 8px; margin-bottom: 12px; box-sizing: border-box; }
table { width: 100%; border-collapse: collapse; background: white; }
th, td { padding: 8px; border-bottom: 1px solid #ddd; text-align: left; }
td.qtd { color: #c0392b; font-weight: bold; text-align: right; }
th { background: #333; color: white; }
</style>
</head>
<body>
<h1>Painel de Estoque Negativos</h1>
<p>Gerado em: $($GeradoEm.ToString('dd/MM/yyyy HH:mm'))</p>
$avisoHtml
<div class="resumo">
<div>Total de itens: <b>$totalItens</b></div>
<div>Lojas afetadas: <b>$lojasAfetadas</b></div>
</div>
<input id="busca" type="text" placeholder="Filtrar por loja ou produto...">
<table id="tabela">
<thead><tr><th>Loja</th><th>Produto</th><th>Código</th><th>Quantidade</th><th>Data</th></tr></thead>
<tbody>
$linhasHtml
</tbody>
</table>
<script>
document.getElementById('busca').addEventListener('input', function (e) {
  var termo = e.target.value.toLowerCase();
  document.querySelectorAll('#tabela tbody tr').forEach(function (tr) {
    var loja = tr.getAttribute('data-loja');
    var produto = tr.getAttribute('data-produto');
    tr.style.display = (loja.indexOf(termo) !== -1 || produto.indexOf(termo) !== -1) ? '' : 'none';
  });
});
</script>
</body>
</html>
"@
}
```

- [ ] **Step 4: Rodar os testes e confirmar que passam**

Run: `Invoke-Pester painel-negativos/negativos-lib.Tests.ps1`
Expected: PASS (todas as `Describe` do arquivo)

- [ ] **Step 5: Commit**

```bash
git add painel-negativos/negativos-lib.ps1 painel-negativos/negativos-lib.Tests.ps1
git commit -m "feat: adiciona renderizacao do painel HTML com busca client-side"
```

---

## Task 4: Script principal com fallback de erro e log

**Files:**
- Create: `painel-negativos/gera-painel-negativos.ps1`

- [ ] **Step 1: Implementar o script principal**

Criar `painel-negativos/gera-painel-negativos.ps1`:

```powershell
param(
    [string]$Server = "192.168.0.55",
    [string]$Database = "Dorinhos_2022",
    [string]$CredPath = "$PSScriptRoot\.sql_cred_negativos.xml",
    [string]$EstadoPath = "$PSScriptRoot\estado\negativos-estado.json",
    [string]$OutputPath = "$PSScriptRoot\web\negativos.html",
    [string]$LogDir = "C:\Logs\PainelNegativos"
)

. "$PSScriptRoot\negativos-lib.ps1"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}
$logFile = Join-Path $LogDir "painel_$(Get-Date -Format 'yyyy-MM-dd').log"

function Write-PainelLog {
    param([string]$Mensagem)
    "$(Get-Date -Format 'u') $Mensagem" | Add-Content -Path $logFile
}

try {
    if (-not (Test-Path $CredPath)) {
        throw "Credencial não encontrada em $CredPath. Rode salvar-credencial.ps1 primeiro."
    }
    $cred = Import-Clixml -Path $CredPath

    $itens = Get-NegativosData -Server $Server -Database $Database -Credential $cred
    $agora = Get-Date

    Save-NegativosEstado -Items $itens -GeradoEm $agora -Path $EstadoPath
    $html = New-PainelHtml -Items $itens -GeradoEm $agora -Desatualizado $false

    Write-PainelLog "OK - $($itens.Count) itens negativos, $((($itens | Select-Object -ExpandProperty loja -Unique).Count)) lojas afetadas"
}
catch {
    Write-PainelLog "ERRO: $($_.Exception.Message)"

    $estadoAnterior = Get-NegativosEstado -Path $EstadoPath
    if ($estadoAnterior) {
        $html = New-PainelHtml -Items $estadoAnterior.Items -GeradoEm ([datetime]$estadoAnterior.GeradoEm) -Desatualizado $true
        Write-PainelLog "Usando ultimo estado bem-sucedido de $($estadoAnterior.GeradoEm)"
    }
    else {
        $html = New-PainelHtml -Items @() -GeradoEm (Get-Date) -Desatualizado $true
        Write-PainelLog "Sem estado anterior disponivel - painel gerado vazio"
    }
}

$outputDir = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
$html | Set-Content -Path $OutputPath -Encoding UTF8
```

- [ ] **Step 2: Testar manualmente com credencial de teste (sem retaguarda real) forçando o caminho de erro**

Run:
```powershell
cd painel-negativos
.\gera-painel-negativos.ps1 -CredPath ".\nao-existe.xml"
Get-Content ".\estado\..\web\negativos.html" -Raw | Select-String "dados desatualizados"
```
Expected: o comando roda sem lançar exceção não tratada, `web\negativos.html` existe e contém "dados desatualizados" (já que não há estado anterior nem credencial válida, mas o painel não quebra)

- [ ] **Step 3: Commit**

```bash
git add painel-negativos/gera-painel-negativos.ps1
git commit -m "feat: adiciona script principal com fallback e log de execucao"
```

---

## Task 5: Credencial SQL e registro da Scheduled Task de geração

**Files:**
- Create: `painel-negativos/salvar-credencial.ps1`
- Create: `painel-negativos/instala-tarefa.ps1`

- [ ] **Step 1: Criar o script de salvamento de credencial**

Criar `painel-negativos/salvar-credencial.ps1`:

```powershell
param(
    [string]$Path = "$PSScriptRoot\.sql_cred_negativos.xml"
)

$cred = Get-Credential -UserName "sa" -Message "Senha do usuario sa na retaguarda (192.168.0.55)"
$cred | Export-Clixml -Path $Path

Write-Host "Credencial salva em $Path (protegida por DPAPI, só abre com este usuario/maquina)."
```

- [ ] **Step 2: Rodar o script de credencial na máquina da Daniella**

Run: `.\painel-negativos\salvar-credencial.ps1`
Expected: prompt de usuário/senha aparece, `.sql_cred_negativos.xml` é criado em `painel-negativos/`

- [ ] **Step 3: Criar o script de instalação da Scheduled Task**

Criar `painel-negativos/instala-tarefa.ps1`:

```powershell
$scriptPath = Join-Path $PSScriptRoot "gera-painel-negativos.ps1"

$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

$trigger = New-ScheduledTaskTrigger -Weekly `
    -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday `
    -At "11:05AM"

Register-ScheduledTask -TaskName "PainelEstoqueNegativos" `
    -Action $action -Trigger $trigger `
    -Description "Gera o painel HTML de estoque negativo a partir da retaguarda" `
    -RunLevel Highest -Force

Write-Host "Tarefa 'PainelEstoqueNegativos' registrada: seg-sex as 11:05."
```

- [ ] **Step 4: Registrar a tarefa e confirmar**

Run: `.\painel-negativos\instala-tarefa.ps1`
Expected: sem erro. Confirmar com `Get-ScheduledTask -TaskName "PainelEstoqueNegativos"` que ela existe e está `Ready`

- [ ] **Step 5: Commit**

```bash
git add painel-negativos/salvar-credencial.ps1 painel-negativos/instala-tarefa.ps1
git commit -m "feat: adiciona scripts de credencial e agendamento da tarefa"
```

---

## Task 6: Servidor web e verificação ponta a ponta

**Files:**
- Create: `painel-negativos/instala-servidor-web.ps1`

- [ ] **Step 1: Criar o script que registra o http.server como tarefa de inicialização**

Criar `painel-negativos/instala-servidor-web.ps1`:

```powershell
param(
    [int]$Porta = 8081
)

$webDir = Join-Path $PSScriptRoot "web"
if (-not (Test-Path $webDir)) {
    New-Item -ItemType Directory -Path $webDir -Force | Out-Null
}

$python = (Get-Command python).Source
$action = New-ScheduledTaskAction -Execute $python `
    -Argument "-m http.server $Porta --directory `"$webDir`"" `
    -WorkingDirectory $webDir

$trigger = New-ScheduledTaskTrigger -AtLogOn

Register-ScheduledTask -TaskName "PainelEstoqueNegativosWeb" `
    -Action $action -Trigger $trigger `
    -Description "Sobe o http.server do painel de estoque negativos na porta $Porta" `
    -RunLevel Highest -Force

Write-Host "Tarefa 'PainelEstoqueNegativosWeb' registrada: inicia http.server na porta $Porta ao logar."
```

- [ ] **Step 2: Registrar a tarefa e iniciar manualmente pela primeira vez**

Run:
```powershell
.\painel-negativos\instala-servidor-web.ps1 -Porta 8081
Start-ScheduledTask -TaskName "PainelEstoqueNegativosWeb"
```
Expected: sem erro. `Get-ScheduledTask -TaskName "PainelEstoqueNegativosWeb"` mostra a tarefa `Running`

- [ ] **Step 3: Rodar o script principal manualmente e verificar o painel no navegador**

Run:
```powershell
.\painel-negativos\gera-painel-negativos.ps1
```
Expected: `painel-negativos\web\negativos.html` é gerado com dados reais da retaguarda

Abrir no navegador: `http://localhost:8081` (na própria máquina) e `http://<ip-da-maquina-da-daniella>:8081` (de outra máquina da rede)
Expected: painel carrega, mostra total de itens/lojas, tabela ordenada por quantidade (mais negativa primeiro), e o campo de busca filtra por loja/produto em tempo real

- [ ] **Step 4: Commit**

```bash
git add painel-negativos/instala-servidor-web.ps1
git commit -m "feat: adiciona registro do servidor web como tarefa de inicializacao"
```

---

## Task 7: Verificação final

- [ ] **Step 1: Rodar toda a suíte de testes Pester**

Run: `Invoke-Pester painel-negativos/negativos-lib.Tests.ps1 -Output Detailed`
Expected: todos os testes passam (0 failed)

- [ ] **Step 2: Confirmar os nomes reais das colunas de `estoque_negativos`**

Run (com a credencial já salva):
```powershell
$cred = Import-Clixml "painel-negativos\.sql_cred_negativos.xml"
Invoke-Sqlcmd -ServerInstance "192.168.0.55" -Database "Dorinhos_2022" -Credential $cred -Query "SELECT TOP 1 * FROM estoque_negativos"
```
Expected: colunas retornadas batem com `loja, produto, codigo, quantidade, data` usados em `Get-NegativosData`. Se os nomes reais forem diferentes, ajustar a query em `negativos-lib.ps1` (Task 1, Step 4) e os testes correspondentes antes de seguir.

- [ ] **Step 3: Deixar a tarefa rodar no próximo dia útil e conferir o log**

Run: `Get-Content "C:\Logs\PainelNegativos\painel_$(Get-Date -Format 'yyyy-MM-dd').log"`
Expected: linha `OK - N itens negativos, M lojas afetadas` sem erro
```
