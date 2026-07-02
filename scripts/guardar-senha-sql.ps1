# =====================================================================
# guardar-senha-sql.ps1 — Grava as senhas do sa protegidas por DPAPI.
# Rode UMA vez (e sempre que a senha mudar). Só o seu usuário descriptografa.
#   .sql_cred            -> senha compartilhada das 38 lojas
#   .sql_cred_retaguarda -> senha da retaguarda (Dorinhos)
# =====================================================================

$lojas = Read-Host -AsSecureString "Senha do sa das LOJAS (compartilhada)"
($lojas | ConvertFrom-SecureString) | Set-Content "C:\Users\Daniella\ti\.sql_cred" -Encoding ASCII

$reta = Read-Host -AsSecureString "Senha do sa da RETAGUARDA (Dorinhos)"
($reta | ConvertFrom-SecureString) | Set-Content "C:\Users\Daniella\ti\.sql_cred_retaguarda" -Encoding ASCII

Write-Host "Senhas gravadas em C:\Users\Daniella\ti\.sql_cred e .sql_cred_retaguarda" -ForegroundColor Green
