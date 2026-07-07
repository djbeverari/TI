param(
    [string]$LibPath = "$PSScriptRoot\conectividade-lib.ps1",
    [string]$ConfigPath = "$PSScriptRoot\scripts\lojas-config.ps1",
    [string]$LogDir = 'C:\Logs\Conectividade',
    [string]$OutputPath = 'C:\WebConectividade\conectividade.html',
    [string]$RankingOutputPath = 'C:\WebConectividade\ranking.html',
    [int]$RankingDias = 7
)

$ErrorActionPreference = 'Stop'
. $LibPath

function Write-LogExecucao {
    param([string]$Mensagem)
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    $arquivo = Join-Path $LogDir ("execucao_{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))
    Add-Content -Path $arquivo -Value "$(Get-Date -Format o) - $Mensagem"
}

try {
    . $ConfigPath
} catch {
    Write-LogExecucao "ERRO ao ler lojas-config.ps1: $($_.Exception.Message)"
    exit 1
}

if (-not (Get-Variable -Name Lojas -ErrorAction SilentlyContinue)) {
    Write-LogExecucao "ERRO: lojas-config.ps1 não definiu a variável `$Lojas"
    exit 1
}

try {
    $resultados = Invoke-CicloConectividade -Lojas $Lojas
    Add-HistoricoConectividade -Linhas $resultados -LogDir $LogDir

    $historico = Get-HistoricoDia -LogDir $LogDir
    New-PainelHtml -Resultados $resultados -Lojas $Lojas -Historico $historico -OutputPath $OutputPath

    Write-LogExecucao "Ciclo concluído: $($resultados.Count) checagens"
} catch {
    Write-LogExecucao "ERRO no ciclo: $($_.Exception.Message)"
    exit 1
}

try {
    $historicoPeriodo = Get-HistoricoPeriodo -LogDir $LogDir -Dias $RankingDias
    $rankingRoteador = Get-RankingInstabilidade -Historico $historicoPeriodo -Tipo 'Roteador' -Top 10
    $rankingMaquina = Get-RankingInstabilidade -Historico $historicoPeriodo -Tipo 'Maquina' -Top 10
    $rankingLatencia = Get-RankingLatencia -Historico $historicoPeriodo -Top 10

    New-RankingHtml -RankingRoteador $rankingRoteador -RankingMaquina $rankingMaquina -RankingLatencia $rankingLatencia -Dias $RankingDias -OutputPath $RankingOutputPath

    Write-LogExecucao "Ranking atualizado ($RankingDias dias de histórico)"
} catch {
    Write-LogExecucao "AVISO: falha ao gerar ranking.html (painel principal já atualizado): $($_.Exception.Message)"
}
