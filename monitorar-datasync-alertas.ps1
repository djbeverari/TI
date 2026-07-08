# Monitorar Data Sync - Alertas por Email
# Roda na sua máquina, monitora logs do servidor e envia alertas

$LogPath = "C:\Logs\DataSync"
$AlertasPath = "$LogPath\alertas_$(Get-Date -Format 'yyyy-MM-dd').log"
$UltimaVerificacao = @{}

# Configurações de Email
$EmailRemetente = "daniella@dorinhos.com.br"
$EmailDestino = "daniella@dorinhos.com.br"
$SmtpServer = "smtp.office365.com"
$SmtpPort = 587
$ArquivoCredencial = "C:\Users\Daniella\ti\.email_cred"

function Enviar-Alerta {
    param(
        [string]$Loja,
        [string]$Erro,
        [string]$Fase,
        [string]$Horario,
        [int]$FalhasTotais,
        [string]$Nivel
    )

    try {
        # Verificar se arquivo de credenciais existe
        if (!(Test-Path $ArquivoCredencial)) {
            Write-Host "[ERRO] Arquivo de credenciais não encontrado!" -ForegroundColor Red
            return
        }

        # Descriptografar a senha
        $senhaSegura = Get-Content $ArquivoCredencial | ConvertTo-SecureString
        $credencial = New-Object System.Management.Automation.PSCredential($EmailRemetente, $senhaSegura)

        # Determinar assunto e corpo baseado no nível
        if ($Nivel -eq "CRÍTICO") {
            $assunto = "🔴 CRÍTICO: Loja $Loja falhou $FalhasTotais vezes!"
            $corpo = @"
🔴 ALERTA CRÍTICO - DATA SYNC

Loja: $Loja
Falhas Hoje: $FalhasTotais
Fase: $Fase
Erro: $Erro
Horário: $Horario

⚠️ AÇÃO IMEDIATA NECESSÁRIA
Verifique o atalho ou a conexão da Loja $Loja no servidor.

Data/Hora: $(Get-Date -Format "dd/MM/yyyy HH:mm:ss")
---
Mensagem automática - Monitorador Data Sync
"@
        } else {
            $assunto = "⚠️ Falha detectada: Loja $Loja"
            $corpo = @"
⚠️ FALHA DETECTADA - DATA SYNC

Loja: $Loja
Fase: $Fase
Erro: $Erro
Horário: $Horario

📋 Ação: Monitorar loja $Loja

Data/Hora: $(Get-Date -Format "dd/MM/yyyy HH:mm:ss")
---
Mensagem automática - Monitorador Data Sync
"@
        }

        $params = @{
            SmtpServer = $SmtpServer
            Port = $SmtpPort
            UseSsl = $true
            Credential = $credencial
            From = $EmailRemetente
            To = $EmailDestino
            Subject = $assunto
            Body = $corpo
        }

        Send-MailMessage @params
        Write-Host "[EMAIL] Alerta enviado para $EmailDestino" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERRO] Falha ao enviar email: $_" -ForegroundColor Red
    }
}

function Log-Local {
    param(
        [string]$Mensagem
    )
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $Entrada = "[$Timestamp] $Mensagem"
    Add-Content -Path $AlertasPath -Value $Entrada -Encoding UTF8
    Write-Host $Entrada -ForegroundColor Yellow
}

function Verificar-Falhas {
    $LogAtual = "$LogPath\sync_$(Get-Date -Format 'yyyy-MM-dd').log"

    if (!(Test-Path $LogAtual)) {
        return
    }

    $Conteudo = Get-Content $LogAtual -Encoding UTF8 -ErrorAction SilentlyContinue
    if (!$Conteudo) { return }

    $Linhas = $Conteudo | Select-String "\[ERROR\]|\[ERRO\]" -AllMatches

    foreach ($Linha in $Linhas) {
        $Texto = $Linha.Line

        # Extrair informações
        if ($Texto -match "Loja (\d+).*-\s+(.+)") {
            $Loja = $matches[1]
            $Erro = $matches[2].Trim()
            $Horario = if ($Texto -match "\[(\d{2}:\d{2}:\d{2})\]") { $matches[1] } else { "??:??:??" }
            $Fase = if ($Texto -match "(RECEBE|ENVIA)") { $matches[1] } else { "DESCONHECIDA" }
        } else {
            continue
        }

        # Chave única para erro
        $Chave = "$Loja-$Erro-$Horario"

        # Verificar se é erro novo
        if (-not $UltimaVerificacao.ContainsKey($Chave)) {
            $UltimaVerificacao[$Chave] = $true

            # Contar falhas da loja hoje
            $FalhasLoja = ($Conteudo | Select-String "Loja $Loja" | Select-String "\[ERROR\]").Count

            # Determinar nível e enviar alerta
            if ($FalhasLoja -ge 2) {
                Log-Local "🔴 CRÍTICO: Loja $Loja falhou $FalhasLoja vezes! Erro: $Erro"
                Enviar-Alerta -Loja $Loja -Erro $Erro -Fase $Fase -Horario $Horario -FalhasTotais $FalhasLoja -Nivel "CRÍTICO"
            } else {
                Log-Local "⚠️ Falha em Loja $Loja ($Fase): $Erro"
                Enviar-Alerta -Loja $Loja -Erro $Erro -Fase $Fase -Horario $Horario -FalhasTotais $FalhasLoja -Nivel "AVISO"
            }
        }
    }
}

# Inicializar
Write-Host "========================================" -ForegroundColor Green
Write-Host "Monitorador Data Sync - Alertas por Email" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Monitorando: $LogPath" -ForegroundColor Cyan
Write-Host "Alertas: $AlertasPath" -ForegroundColor Cyan
Write-Host "Email: $EmailDestino" -ForegroundColor Cyan
Write-Host "Status: ATIVO ✅" -ForegroundColor Green
Write-Host "Pressione CTRL+C para parar" -ForegroundColor Yellow
Write-Host ""

# Loop infinito
while ($true) {
    try {
        Verificar-Falhas
        Start-Sleep -Seconds 30
    }
    catch {
        Log-Local "Erro: $_"
        Start-Sleep -Seconds 30
    }
}
