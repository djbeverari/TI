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
