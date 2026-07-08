# ============================================================
# Guardar credenciais de email no Windows Credential Manager
# Execute uma única vez para armazenar a senha
# ============================================================

Write-Host "Guardando credenciais de email no Windows..." -ForegroundColor Green
Write-Host ""

$email = "daniella@dorinhos.com.br"
$senha = Read-Host "Digite a senha do email $email" -AsSecureString

# Converter para texto plano para armazenar
$senhaPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemAlloc($senha))

# Guardar no Credential Manager do Windows
$credentialTarget = "DataSyncEmail"

# Usar cmdlet para guardar (requer admin em alguns casos)
try {
    $credencial = New-Object System.Management.Automation.PSCredential($email, $senha)

    # Guardar usando Windows Credential Manager
    cmdkey /add:$credentialTarget /user:$email /pass:$senhaPlain

    Write-Host ""
    Write-Host "✅ Credenciais guardadas com sucesso!" -ForegroundColor Green
    Write-Host "Target: $credentialTarget" -ForegroundColor Cyan
    Write-Host "Email: $email" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Agora o script pode usar a senha automaticamente!" -ForegroundColor Yellow
}
catch {
    Write-Host "❌ Erro ao guardar credenciais: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Se receberr erro de permissão, execute este script como Admin" -ForegroundColor Yellow
}
