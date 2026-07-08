# Servidor HTTP - Painel Data Sync
# Acessivel em http://192.168.0.147:8080/painel.html de qualquer maquina da rede
# Execute como Administrador para abrir a porta no firewall

param(
    [int]$Porta = 8080,
    [string]$PastaLogs = "C:\Logs\DataSync",
    [string]$CredencialPainelProtegido = "$PSScriptRoot\.painel_vendas_cred"
)

# Paineis que exigem usuario/senha (Basic Auth) - guardados via
# guardar-senha-painel-vendas.ps1. Os demais paineis (painel.html, tickets.html)
# continuam sem senha.
$PadroesProtegidos = @('vendas*')

function Set-CabecalhoSemValidacao {
    # HttpListenerResponse bloqueia Headers.Add/Set(nome, valor) e mesmo
    # Add("Nome: Valor") para o header WWW-Authenticate ("deve ser
    # modificado com a propriedade ou metodo adequado"). AddWithoutValidate
    # (metodo interno do WebHeaderCollection) contorna essa checagem - e o
    # workaround padrao conhecido para esse problema do .NET.
    param($Response, [string]$Nome, [string]$Valor)
    $metodo = $Response.Headers.GetType().GetMethod('AddWithoutValidate', [System.Reflection.BindingFlags]'NonPublic,Instance')
    $metodo.Invoke($Response.Headers, @($Nome, $Valor))
}

function Test-CaminhoProtegido {
    param([string]$UrlPath)
    foreach ($padrao in $PadroesProtegidos) {
        if ($UrlPath -like $padrao) { return $true }
    }
    return $false
}

function Test-AutenticacaoBasica {
    param([string]$AuthorizationHeader)
    $existeCredencial = Test-Path $CredencialPainelProtegido
    $temHeader = -not [string]::IsNullOrEmpty($AuthorizationHeader)
    try {
        Add-Content -Path "$PSScriptRoot\servidor-http-debug.log" -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') DEBUG: CredencialPainelProtegido='$CredencialPainelProtegido' existe=$existeCredencial temHeaderAuthorization=$temHeader" -Encoding UTF8
    } catch {}
    if (-not $existeCredencial) {
        # Sem credencial guardada: nao bloqueia (evita travar o painel se
        # ninguem rodou guardar-senha-painel-vendas.ps1 ainda).
        return $true
    }
    if (-not $AuthorizationHeader -or -not $AuthorizationHeader.StartsWith('Basic ')) {
        return $false
    }
    try {
        $b64 = $AuthorizationHeader.Substring(6)
        $decodificado = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
        $separador = $decodificado.IndexOf(':')
        if ($separador -lt 0) { return $false }
        $usuarioEnviado = $decodificado.Substring(0, $separador)
        $senhaEnviada   = $decodificado.Substring($separador + 1)

        $credSalva = Import-Clixml -Path $CredencialPainelProtegido
        $senhaSalva = $credSalva.GetNetworkCredential().Password
        return ($usuarioEnviado -eq $credSalva.UserName -and $senhaEnviada -eq $senhaSalva)
    } catch {
        return $false
    }
}

# Registrar URL no Windows (requer admin)
$prefix = "http://+:$Porta/"
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "SERVIDOR HTTP - PAINEL DATA SYNC" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "URL: http://192.168.0.147:$Porta/painel.html" -ForegroundColor Cyan
    Write-Host "Servindo arquivos de: $PastaLogs" -ForegroundColor Cyan
    Write-Host "Pressione CTRL+C para parar." -ForegroundColor Yellow
    Write-Host ""
}
catch {
    Write-Host "ERRO ao iniciar servidor: $_" -ForegroundColor Red
    Write-Host "Solucao: Execute como Administrador" -ForegroundColor Yellow
    exit 1
}

$mimeTypes = @{
    ".html" = "text/html; charset=utf-8"
    ".css"  = "text/css"
    ".js"   = "application/javascript"
    ".json" = "application/json"
    ".txt"  = "text/plain; charset=utf-8"
    ".log"  = "text/plain; charset=utf-8"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".ico"  = "image/x-icon"
}

while ($listener.IsListening) {
    try {
        $context  = $listener.GetContext()
        $request  = $context.Request
        $response = $context.Response

        $urlPath = $request.Url.LocalPath.TrimStart('/')
        if ([string]::IsNullOrEmpty($urlPath) -or $urlPath -eq '/') {
            $urlPath = 'painel.html'
        }

        if ((Test-CaminhoProtegido -UrlPath $urlPath) -and -not (Test-AutenticacaoBasica -AuthorizationHeader $request.Headers["Authorization"])) {
            try {
                Set-CabecalhoSemValidacao -Response $response -Nome 'WWW-Authenticate' -Valor 'Basic realm="Painel de Vendas"'
                $msg = [System.Text.Encoding]::UTF8.GetBytes("<h1>401 - Autenticacao necessaria</h1>")
                $response.ContentType = "text/html; charset=utf-8"
                $response.StatusCode = 401
                $response.ContentLength64 = $msg.Length
                $response.OutputStream.Write($msg, 0, $msg.Length)
                Write-Host "$(Get-Date -Format 'HH:mm:ss') GET /$urlPath -> 401 (sem autenticacao)" -ForegroundColor Yellow
            } catch {
                $erro = $_
                Write-Host "Erro ao montar resposta 401: $erro" -ForegroundColor Red
                try { Add-Content -Path "$PSScriptRoot\servidor-http-erros.log" -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ERRO 401: $erro`n$($erro.ScriptStackTrace)" -Encoding UTF8 } catch {}
            } finally {
                $response.Close()
            }
            continue
        }

        $filePath = Join-Path $PastaLogs $urlPath

        if (Test-Path $filePath -PathType Leaf) {
            $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
            $contentType = if ($mimeTypes.ContainsKey($ext)) { $mimeTypes[$ext] } else { "application/octet-stream" }

            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            $response.StatusCode    = 200
            $response.ContentType   = $contentType
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)

            Write-Host "$(Get-Date -Format 'HH:mm:ss') GET /$urlPath -> 200" -ForegroundColor Green
        }
        else {
            $msg = [System.Text.Encoding]::UTF8.GetBytes("<h1>404 - Arquivo nao encontrado</h1><p>$urlPath</p>")
            $response.StatusCode    = 404
            $response.ContentType   = "text/html; charset=utf-8"
            $response.ContentLength64 = $msg.Length
            $response.OutputStream.Write($msg, 0, $msg.Length)

            Write-Host "$(Get-Date -Format 'HH:mm:ss') GET /$urlPath -> 404" -ForegroundColor Red
        }

        $response.Close()
    }
    catch {
        $erro = $_
        Write-Host "Erro na requisicao: $erro" -ForegroundColor Red
        try { Add-Content -Path "$PSScriptRoot\servidor-http-erros.log" -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ERRO: $erro`n$($erro.ScriptStackTrace)" -Encoding UTF8 } catch {}
    }
}
