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
    # Usa System.Data.SqlClient diretamente (parte do .NET Framework, sem
    # depender do modulo SqlServer/Invoke-Sqlcmd - o servidor de automacao
    # (192.168.0.147) nao tem esse modulo instalado).
    param(
        [Parameter(Mandatory)][string]$Query,
        [string]$ServidorRetaguarda = "192.168.0.55",
        [string]$BancoRetaguarda = "Dorinhos_2022"
    )
    $cred = Get-CredencialRetaguarda
    $senha = $cred.GetNetworkCredential().Password
    $connectionString = "Server=$ServidorRetaguarda;Database=$BancoRetaguarda;User Id=$($cred.UserName);Password=$senha;TrustServerCertificate=True;"

    $connection = New-Object System.Data.SqlClient.SqlConnection $connectionString
    try {
        $connection.Open()
        $command = New-Object System.Data.SqlClient.SqlCommand $Query, $connection
        $command.CommandTimeout = 60
        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
        $table = New-Object System.Data.DataTable
        [void]$adapter.Fill($table)
        $table.Rows
    } finally {
        $connection.Close()
    }
}
