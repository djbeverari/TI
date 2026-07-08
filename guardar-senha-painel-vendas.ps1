# ============================================================
# Guardar usuario/senha de acesso ao painel de vendas (vendas.html)
# Execute UMA VEZ NO SERVIDOR (192.168.0.147), como o usuario Datasync,
# para nao precisar reiniciar o DataSyncHTTP toda vez que trocar a senha.
# ============================================================

Write-Host "Guardando credencial de acesso ao painel de vendas..." -ForegroundColor Green
Write-Host ""

$usuario = Read-Host "Digite o usuario de acesso ao painel de vendas"
$senhaSegura = Read-Host "Digite a senha de acesso ao painel de vendas" -AsSecureString

$credencial = New-Object System.Management.Automation.PSCredential($usuario, $senhaSegura)
$arquivoCredencial = "$PSScriptRoot\.painel_vendas_cred"

$credencial | Export-Clixml -Path $arquivoCredencial -Force

Write-Host ""
Write-Host "✅ Credencial guardada com sucesso!" -ForegroundColor Green
Write-Host "Arquivo: $arquivoCredencial" -ForegroundColor Cyan
Write-Host ""
Write-Host "O DataSyncHTTP ja usa essa credencial na proxima requisicao" -ForegroundColor Yellow
Write-Host "(nao precisa reiniciar o servidor)." -ForegroundColor Yellow
