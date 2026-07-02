# =====================================================================
# deploy-verificador.ps1 — Roda da SUA máquina (Daniella).
# Copia os scripts do verificador pro servidor via PSRemoting, grava as
# senhas do sa (criptografadas como Datasync, no servidor) e faz o dry-run.
# Uso:  .\deploy-verificador.ps1
# =====================================================================
$ErrorActionPreference = 'Stop'
$src       = $PSScriptRoot
$Servidor  = '192.168.0.147'
$RemoteDir = 'C:\Users\Datasync\Desktop\ti'

Write-Host "== Deploy do Verificador de Tickets ==" -ForegroundColor Cyan

# 1) Credencial do Windows do servidor (conta Datasync)
$cred = Get-Credential -UserName 'Datasync' -Message "Senha do usuario Datasync no servidor $Servidor"
$sess = New-PSSession -ComputerName $Servidor -Credential $cred

try {
    # 2) Copiar os scripts (versao corrigida) pro servidor
    $arquivos = 'tickets-lib.ps1','lojas-config.ps1','verifica-tickets.ps1','guardar-senha-sql.ps1','feriados_municipais.csv'
    foreach ($a in $arquivos) {
        Copy-Item -Path (Join-Path $src $a) -Destination $RemoteDir -ToSession $sess -Force
        Write-Host "  copiado: $a" -ForegroundColor Green
    }

    # 3) Senhas do sa (digitadas aqui; criptografadas la, como Datasync)
    $pwLojas = Read-Host -AsSecureString "Senha do sa das LOJAS (compartilhada)"
    $pwReta  = Read-Host -AsSecureString "Senha do sa da RETAGUARDA (Dorinhos)"

    # 4) Gravar credenciais e rodar o verificador NO SERVIDOR
    $resultado = Invoke-Command -Session $sess -ArgumentList $RemoteDir, $pwLojas, $pwReta -ScriptBlock {
        param($dir, $secLojas, $secReta)
        ($secLojas | ConvertFrom-SecureString) | Set-Content (Join-Path $dir '.sql_cred')            -Encoding ASCII
        ($secReta  | ConvertFrom-SecureString) | Set-Content (Join-Path $dir '.sql_cred_retaguarda') -Encoding ASCII

        Set-Location $dir
        $saida = & powershell -ExecutionPolicy Bypass -File (Join-Path $dir 'verifica-tickets.ps1') *>&1 | Out-String

        $htmlPath = 'C:\WebRelatorios\tickets.html'
        [pscustomobject]@{
            Saida     = $saida
            HtmlExiste= (Test-Path $htmlPath)
            HtmlHora  = if (Test-Path $htmlPath) { (Get-Item $htmlPath).LastWriteTime } else { $null }
            LogTail   = (Get-ChildItem 'C:\Logs\VerificaTickets\*.log' -ErrorAction SilentlyContinue |
                         Sort-Object LastWriteTime | Select-Object -Last 1 |
                         Get-Content -Tail 15 -ErrorAction SilentlyContinue) -join "`n"
        }
    }

    Write-Host "`n--- Saida do verifica-tickets.ps1 ---" -ForegroundColor Cyan
    Write-Host $resultado.Saida
    Write-Host "--- Log (fim) ---" -ForegroundColor Cyan
    Write-Host $resultado.LogTail
    Write-Host "`ntickets.html existe: $($resultado.HtmlExiste)  ($($resultado.HtmlHora))" -ForegroundColor $(if($resultado.HtmlExiste){'Green'}else{'Red'})
    if ($resultado.HtmlExiste) {
        Write-Host "Abra: http://192.168.0.147:8080/tickets.html" -ForegroundColor Cyan
    }
}
finally {
    Remove-PSSession $sess
}
