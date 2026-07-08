# ============================================================
# Guardar senha de email de forma criptografada
# Execute uma única vez para armazenar
# ============================================================

Write-Host "Guardando senha de email criptografada..." -ForegroundColor Green
Write-Host ""

$email = "daniella@dorinhos.com.br"
$senhaSegura = Read-Host "Digite a senha do email" -AsSecureString
$arquivoCredencial = "C:\Users\Daniella\ti\.email_cred"

# Criptografar e guardar (será específico do usuário)
$senhaSegura | ConvertFrom-SecureString | Set-Content $arquivoCredencial -Force

Write-Host ""
Write-Host "✅ Senha guardada com sucesso!" -ForegroundColor Green
Write-Host "Arquivo: $arquivoCredencial" -ForegroundColor Cyan
Write-Host ""
Write-Host "A senha será usada automaticamente pelo script!" -ForegroundColor Yellow
