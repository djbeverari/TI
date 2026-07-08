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
