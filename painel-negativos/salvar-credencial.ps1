param(
    [string]$Path = "$PSScriptRoot\.sql_cred_negativos.xml"
)

$cred = Get-Credential -UserName "sa" -Message "Senha do usuario sa na retaguarda (192.168.0.55)"
$cred | Export-Clixml -Path $Path

Write-Host "Credencial salva em $Path (protegida por DPAPI, só abre com este usuario/maquina)."
