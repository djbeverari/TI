# =====================================================================
# guardar-senha-sql.ps1 — Grava as senhas do sa protegidas por DPAPI.
# Rode UMA vez (e sempre que a senha mudar). Só o seu usuário descriptografa.
#   .sql_cred            -> senha compartilhada das 38 lojas
#   .sql_cred_retaguarda -> senha da retaguarda (Dorinhos)
# =====================================================================

# Grava as senhas na MESMA pasta deste script (funciona local e no servidor).
$destLojas = Join-Path $PSScriptRoot ".sql_cred"
$destReta  = Join-Path $PSScriptRoot ".sql_cred_retaguarda"

$lojas = Read-Host -AsSecureString "Senha do sa das LOJAS (compartilhada)"
($lojas | ConvertFrom-SecureString) | Set-Content $destLojas -Encoding ASCII

$reta = Read-Host -AsSecureString "Senha do sa da RETAGUARDA (Dorinhos)"
($reta | ConvertFrom-SecureString) | Set-Content $destReta -Encoding ASCII

Write-Host "Senhas gravadas em:" -ForegroundColor Green
Write-Host "  $destLojas"
Write-Host "  $destReta"
