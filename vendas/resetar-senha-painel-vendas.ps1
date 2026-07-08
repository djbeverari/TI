# RESETAR - usuario/senha de acesso ao painel de vendas (vendas.html)
# Nao precisa reiniciar o servidor - a credencial e lida do arquivo a
# cada requisicao.
# Execute com: powershell -ExecutionPolicy Bypass -File "resetar-senha-painel-vendas.ps1"

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host " RESETAR - Senha do Painel de Vendas" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Usuario Datasync no servidor 192.168.0.147:" -ForegroundColor Yellow
$senhaServidor = Read-Host "Senha do usuario Datasync" -AsSecureString
$credServidor = New-Object System.Management.Automation.PSCredential("Datasync", $senhaServidor)

Write-Host ""
Write-Host "Novo usuario/senha de acesso ao painel de vendas:" -ForegroundColor Yellow
$usuarioPainel = Read-Host "Usuario de acesso ao painel de vendas"
$senhaPainel = Read-Host "Senha de acesso ao painel de vendas" -AsSecureString
$credPainel = New-Object System.Management.Automation.PSCredential($usuarioPainel, $senhaPainel)

Write-Host ""
Write-Host "Conectando ao servidor..." -ForegroundColor Cyan
$session = New-PSSession -ComputerName 192.168.0.147 -Credential $credServidor -ErrorAction Stop

Invoke-Command -Session $session -ScriptBlock {
    param($credPainel)
    $tiDir = "C:\Users\Datasync\Desktop\ti"
    $credPainel | Export-Clixml -Path "$tiDir\.painel_vendas_cred" -Force
    Write-Host "[OK] Credencial do painel de vendas atualizada (usuario: $($credPainel.UserName))" -ForegroundColor Green
} -ArgumentList $credPainel

Remove-PSSession $session

Write-Host ""
Write-Host "================================================" -ForegroundColor Green
Write-Host " SENHA RESETADA! Ja vale na proxima requisicao," -ForegroundColor Green
Write-Host " sem precisar reiniciar nada." -ForegroundColor Green
Write-Host " Teste: http://192.168.0.147:8080/vendas.html" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Green
Write-Host ""
pause
