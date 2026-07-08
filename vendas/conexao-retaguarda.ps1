# ============================================================
# Conexao reutilizavel com a retaguarda (Dorinhos_2022 @ 192.168.0.55)
# ============================================================

function Get-CredencialRetaguarda {
    param(
        [string]$CaminhoCredencial = "$PSScriptRoot\.sql_cred_retaguarda"
    )
    if (-not (Test-Path $CaminhoCredencial)) {
        throw "Credencial não encontrada em $CaminhoCredencial. Rode guardar-senha-sql-retaguarda.ps1 primeiro."
    }
    Import-Clixml -Path $CaminhoCredencial
}

function Invoke-QueryRetaguarda {
    param(
        [Parameter(Mandatory)][string]$Query,
        [string]$ServidorRetaguarda = "192.168.0.55",
        [string]$BancoRetaguarda = "Dorinhos_2022"
    )
    $cred = Get-CredencialRetaguarda
    $senha = $cred.GetNetworkCredential().Password
    Invoke-Sqlcmd -ServerInstance $ServidorRetaguarda `
                   -Database $BancoRetaguarda `
                   -Username $cred.UserName `
                   -Password $senha `
                   -TrustServerCertificate `
                   -Query $Query
}
