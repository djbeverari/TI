# =====================================================================
# verifica-tickets.ps1 — Orquestrador do Verificador de Tickets
# Compara a contagem de tickets de cada loja com a retaguarda e gera o painel.
# Agendado ~11:30 (após o ciclo DataSync_1030), seg–sex.
# =====================================================================
$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot
. (Join-Path $base 'lojas-config.ps1')
. (Join-Path $base 'tickets-lib.ps1')

# --- Caminhos --------------------------------------------------------
$LogDir        = 'C:\Logs\VerificaTickets'
$SaidaHtml     = 'C:\Logs\DataSync\tickets.html'
$CacheFeriados = Join-Path $base 'feriados_cache.json'
$CsvMunicipal  = Join-Path $base 'feriados_municipais.csv'
$StatusDir     = 'C:\Logs\DataSync\status'   # status do datasync (loja_<num>.txt)
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Write-VerificaLog {
    param([string]$Msg, [string]$Nivel = 'INFO')
    $ts  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $arq = Join-Path $LogDir ("verifica_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))
    Add-Content -Path $arq -Value "[$ts] [$Nivel] $Msg"
}

function Read-SqlSenha {
    param([string]$Arquivo)
    $sec = Get-Content $Arquivo | ConvertTo-SecureString
    [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}

# --- Senhas (lojas e retaguarda são diferentes) ----------------------
$pwLojas      = Read-SqlSenha $SqlCredFile
$pwRetaguarda = Read-SqlSenha $SqlCredFileRetaguarda

$hoje = Get-Date
$ano  = $hoje.Year
Write-VerificaLog "Inicio da verificacao (ref=$($hoje.ToString('yyyy-MM-dd')))"

$feriadosNac = Get-FeriadosNacionais -Ano $ano -CacheFile $CacheFeriados

$resultados = foreach ($loja in $Lojas) {
    $feriados = @()
    $feriados += $feriadosNac
    $feriados += Get-FeriadosMunicipais -Csv $CsvMunicipal -Loja $loja.Numero
    $datas = Get-DatasParaVerificar -Referencia $hoje -Feriados $feriados

    $erro = $false; $tl = 0; $tr = 0
    try {
        $tl = Get-TicketCount -Servidor $loja.Servidor -Banco $loja.Banco -Usuario $SqlUser -Senha $pwLojas `
                              -Datas $datas -ColunaLoja $ColunaLojaLocal -Loja $loja.Numero
        $tr = Get-TicketCount -Servidor $Retaguarda.Servidor -Banco $BancoRetaguarda -Usuario $SqlUser -Senha $pwRetaguarda `
                              -Datas $datas -ColunaLoja $ColunaLojaRetaguarda -Loja $loja.Numero
    } catch {
        $erro = $true
        Write-VerificaLog "Loja $($loja.Numero): erro de conexao - $($_.Exception.Message)" 'ERROR'
    }
    $sync   = Get-SyncConcluidoLoja -Loja $loja.Numero -StatusDir $StatusDir -Hoje $hoje
    $status = Get-TicketStatus -TicketsLoja $tl -TicketsRetaguarda $tr -SyncConcluido $sync -ErroConexao $erro

    [pscustomobject]@{
        Loja=$loja.Numero; TicketsLoja=$tl; TicketsRetaguarda=$tr;
        Diferenca=($tl - $tr); SyncConcluido=$sync; Status=$status
    }
}

$ciclos = foreach ($nomeTarefa in 'DataSync_1030', 'DataSync_1430', 'DataSync_1630') {
    # Consulta best-effort: se o Task Scheduler falhar aqui (ex.: sessao sem
    # acesso ao WMI de tarefas), o banner de ciclos fica sem essa entrada,
    # mas a comparacao de tickets (o que importa) nao pode ser derrubada.
    try {
        $tarefa = Get-ScheduledTask -TaskName $nomeTarefa -ErrorAction Stop
        $info   = $tarefa | Get-ScheduledTaskInfo -ErrorAction Stop
        Get-StatusCiclo -Nome ($nomeTarefa -replace '_', ' ') -UltimaExecucao $info.LastRunTime `
                        -UltimoResultado $info.LastTaskResult -Hoje $hoje
    } catch {
        Write-VerificaLog "Nao foi possivel consultar status de $nomeTarefa`: $($_.Exception.Message)" 'WARN'
    }
}

$periodo = (Get-DatasParaVerificar -Referencia $hoje -Feriados @() |
            ForEach-Object { $_.ToString('dd/MM') }) -join ', '
$html = New-RelatorioHtml -Resultados $resultados -Periodo $periodo -Timestamp $hoje.ToString('yyyy-MM-dd HH:mm') -Ciclos $ciclos
if (-not (Test-Path (Split-Path $SaidaHtml))) { New-Item -ItemType Directory -Path (Split-Path $SaidaHtml) -Force | Out-Null }
Set-Content -Path $SaidaHtml -Value $html -Encoding UTF8

$div  = ($resultados | Where-Object Status -eq 'DIVERGENTE').Count
$pend = ($resultados | Where-Object Status -eq 'PENDENTE').Count
$errs = ($resultados | Where-Object Status -eq 'ERRO').Count
Write-VerificaLog "Fim. Divergentes=$div Pendentes=$pend Erros=$errs -> $SaidaHtml"
