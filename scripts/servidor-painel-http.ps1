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
        $bytesDecodificados = [Convert]::FromBase64String($AuthorizationHeader.Substring(6))
        $credSalva = Import-Clixml -Path $CredencialPainelProtegido
        $senhaSalva = $credSalva.GetNetworkCredential().Password

        # Tenta UTF-8 primeiro (RFC 7617, o que pedimos via charset="UTF-8"), e
        # cai para Latin-1 (ISO-8859-1, padrao antigo) se nao bater - cobre
        # navegadores/prompts que ainda mandam em Latin-1 quando a senha tem
        # acento ou caractere especial.
        foreach ($encoding in @([System.Text.Encoding]::UTF8, [System.Text.Encoding]::GetEncoding('ISO-8859-1'))) {
            $decodificado = $encoding.GetString($bytesDecodificados)
            $separador = $decodificado.IndexOf(':')
            if ($separador -lt 0) { continue }
            $usuarioEnviado = $decodificado.Substring(0, $separador)
            $senhaEnviada   = $decodificado.Substring($separador + 1)
            $usuarioBate = ($usuarioEnviado -eq $credSalva.UserName)
            $senhaBate   = ($senhaEnviada -eq $senhaSalva)
            try {
                Add-Content -Path "$PSScriptRoot\servidor-http-debug.log" -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') DEBUG-AUTH: encoding=$($encoding.EncodingName) tamanhoUsuarioEnviado=$($usuarioEnviado.Length) tamanhoUsuarioSalvo=$($credSalva.UserName.Length) usuarioBate=$usuarioBate tamanhoSenhaEnviada=$($senhaEnviada.Length) tamanhoSenhaSalva=$($senhaSalva.Length) senhaBate=$senhaBate" -Encoding UTF8
            } catch {}
            if ($usuarioBate -and $senhaBate) {
                return $true
            }
        }
        return $false
    } catch {
        $erro = $_
        try {
            Add-Content -Path "$PSScriptRoot\servidor-http-debug.log" -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') DEBUG-AUTH-EXCECAO: $erro" -Encoding UTF8
        } catch {}
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

function Send-HtmlResponse {
    param($Response, [string]$Html, [int]$StatusCode = 200)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Html)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = "text/html; charset=utf-8"
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.Close()
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
                # charset="UTF-8" (RFC 7617) avisa o navegador para codificar
                # usuario/senha em UTF-8 no popup nativo - sem isso, senhas com
                # acento/caractere especial sao enviadas em Latin-1 e nunca batem
                # com a comparacao em UTF-8 abaixo.
                Set-CabecalhoSemValidacao -Response $response -Nome 'WWW-Authenticate' -Valor 'Basic realm="Painel de Vendas", charset="UTF-8"'
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

        if ($urlPath -eq 'verificacao-timestamp') {
            $arqTickets = Join-Path $PastaLogs 'tickets.html'
            $ts = if (Test-Path $arqTickets) { (Get-Item $arqTickets).LastWriteTimeUtc.ToString('o') } else { '' }
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($ts)
            $response.StatusCode = 200
            $response.ContentType = 'text/plain; charset=utf-8'
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
            $response.Close()
            continue
        }

        if ($urlPath -eq 'executar-verificacao-tickets') {
            $arqTickets = Join-Path $PastaLogs 'tickets.html'
            $tsAntes = if (Test-Path $arqTickets) { (Get-Item $arqTickets).LastWriteTimeUtc.ToString('o') } else { '' }
            try {
                Start-ScheduledTask -TaskName 'VerificaTickets' -ErrorAction Stop
                $msg = 'Verificação disparada.'
                Write-Host "$(Get-Date -Format 'HH:mm:ss') GET /$urlPath -> 200 (gatilho VerificaTickets)" -ForegroundColor Cyan
            } catch {
                $msg = "Não foi possível iniciar a verificação: $($_.Exception.Message)"
                Write-Host "$(Get-Date -Format 'HH:mm:ss') GET /$urlPath -> erro ao disparar tarefa: $_" -ForegroundColor Red
            }
            # Espera ativa via JS: consulta /verificacao-timestamp ate o tickets.html mudar
            # de verdade, em vez de um tempo fixo -- de manha cedo (antes do ciclo das 10:30)
            # varias lojas ainda estao offline e cada erro de conexao leva ~20s, entao a
            # verificacao pode passar bem de 1 minuto.
            $html = @"
<!doctype html><html lang='pt-br'><head><meta charset='utf-8'>
<title>Atualizando...</title>
<style>
body{font-family:'Segoe UI',Arial,sans-serif;background:#0033A0;color:#fff;margin:0;
  height:100vh;display:flex;align-items:center;justify-content:center}
.box{background:#022266;padding:32px 44px;border-radius:10px;border-top:4px solid #FFD700;
  text-align:center;max-width:440px}
a{color:#FFD700}
#aviso{display:none;margin-top:10px;font-size:13px;color:#cfd8f5}
</style></head><body>
<div class='box'>
  <h2>Atualizando verificação de tickets…</h2>
  <p>$msg</p>
  <p id='status'>Aguardando conclusão (isso leva ~1 min, mas pode demorar mais de manhã cedo, com lojas ainda offline)…</p>
  <p id='aviso'>Ainda rodando — normal se muitas lojas ainda não abriram ou o ciclo das 10:30 ainda não passou.</p>
  <p><a href='/tickets.html'>Ir para o painel agora</a></p>
</div>
<script>
var tsAntes = '$tsAntes';
var tentativas = 0;
function checar(){
  tentativas++;
  if (tentativas === 12) { document.getElementById('aviso').style.display = 'block'; }
  fetch('/verificacao-timestamp').then(function(r){ return r.text(); }).then(function(ts){
    if (ts && ts !== tsAntes) { window.location.href = '/tickets.html'; }
    else { setTimeout(checar, 5000); }
  }).catch(function(){ setTimeout(checar, 5000); });
}
setTimeout(checar, 5000);
</script>
</body></html>
"@
            Send-HtmlResponse -Response $response -Html $html
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

