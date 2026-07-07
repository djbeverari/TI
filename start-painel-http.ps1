param(
    [string]$Pasta = 'C:\WebConectividade',
    [int]$Porta = 8081
)

if (-not (Test-Path $Pasta)) {
    New-Item -ItemType Directory -Path $Pasta -Force | Out-Null
}

Set-Location $Pasta
Write-Host "Servindo $Pasta em http://localhost:$Porta (Ctrl+C para parar)"
python -m http.server $Porta
