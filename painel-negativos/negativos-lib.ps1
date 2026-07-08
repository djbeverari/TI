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
