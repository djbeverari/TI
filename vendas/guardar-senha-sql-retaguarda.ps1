# ============================================================
# Guardar senha SQL da retaguarda (Dorinhos_2022 @ 192.168.0.55)
# de forma criptografada (DPAPI - só descriptografa com seu
# usuário/máquina). Execute uma única vez para armazenar.
# ============================================================

Write-Host "Guardando credencial SQL da retaguarda..." -ForegroundColor Green
Write-Host ""

$usuario = Read-Host "Digite o usuário SQL da retaguarda (ex: sa)"
$senhaSegura = Read-Host "Digite a senha SQL da retaguarda" -AsSecureString

$credencial = New-Object System.Management.Automation.PSCredential($usuario, $senhaSegura)
$arquivoCredencial = "C:\Users\Daniella\ti\vendas\.sql_cred_retaguarda"

$credencial | Export-Clixml -Path $arquivoCredencial -Force

Write-Host ""
Write-Host "✅ Credencial guardada com sucesso!" -ForegroundColor Green
Write-Host "Arquivo: $arquivoCredencial" -ForegroundColor Cyan
Write-Host ""
Write-Host "Será usada automaticamente pelo schema-explorer.ps1!" -ForegroundColor Yellow
