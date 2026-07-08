# Manual Técnico - Data Sync Automação 38 Lojas

## 📋 Índice
1. [Visão Geral](#visão-geral)
2. [Arquitetura](#arquitetura)
3. [Instalação e Configuração](#instalação-e-configuração)
4. [Operação e Monitoramento](#operação-e-monitoramento)
5. [Troubleshooting](#troubleshooting)
6. [Referência Técnica](#referência-técnica)

---

## 🎯 Visão Geral

O sistema **Data Sync Automação** sincroniza dados de 38 filiais da Dorinhos com o servidor central (192.168.0.147) automaticamente três vezes ao dia:
- **10:30** — Sincronização matinal
- **14:30** — Sincronização vespertina  
- **16:30** — Sincronização noturna

### O que o sistema faz?

1. **Recebe dados** de todas as 38 lojas do servidor (RECEBE)
2. **Aguarda 10 minutos** para processamento
3. **Envia dados** processados de volta para as 38 lojas (ENVIA)
4. **Registra tudo** em arquivo de log
5. **Notifica erros** por desktop popup e email

---

## 🏗️ Arquitetura

### Fluxo de Execução

```
INÍCIO (10:30, 14:30 ou 16:30)
│
├─ FASE 1: RECEBE (Todos os lojas em série)
│  ├─ Loja 03: RECEBE ✓
│  ├─ Loja 04: RECEBE ✓
│  ├─ ...
│  └─ Loja 57: RECEBE ✓
│
├─ PAUSA: 10 minutos
│  └─ Aguardando processamento no servidor
│
├─ FASE 2: ENVIA (Todos os lojas em série)
│  ├─ Loja 03: ENVIA ✓
│  ├─ Loja 04: ENVIA ✓
│  ├─ ...
│  └─ Loja 57: ENVIA ✓
│
└─ FIM: Relatório + Notificações (se houver erros)
```

### Componentes do Sistema

| Componente | Localização | Função |
|-----------|------------|--------|
| **Script Principal** | `C:\Users\Daniella\ti\data-sync-automacao.ps1` | Executa sincronização de dados |
| **Agendador** | `C:\Users\Daniella\ti\agendar-datasync-admin.ps1` | Cria tarefas no Windows Task Scheduler |
| **Credencial** | `C:\Users\Daniella\ti\.email_cred` | Senha criptografada para email |
| **VBS Remoto** | `\\192.168.0.147\Users\Datasync\Desktop\executar_atalho.vbs` | Executa atalhos no servidor |
| **Logs** | `C:\Logs\DataSync\sync_YYYY-MM-DD.log` | Registro detalhado de execução |

### Fluxo de Dados

```
PowerShell Local
    ↓
    └─→ cscript.exe executa VBScript remoto
            ↓
            └─→ Servidor 192.168.0.147
                    ↓
                    ├─→ RECEBE atalhos
                    │   └─→ DSRetail.exe (Linx Datasync)
                    │       └─→ Download de dados
                    │
                    └─→ ENVIA atalhos
                        └─→ DSRetail.exe (Linx Datasync)
                            └─→ Upload de dados
```

---

## ⚙️ Instalação e Configuração

### Pré-requisitos

- ✅ Windows Server ou Windows 10/11
- ✅ PowerShell 5.0+
- ✅ Acesso de Administrador
- ✅ Conexão de rede para 192.168.0.147
- ✅ Office365/Outlook (para alertas por email)

### Etapa 1: Verificar Arquivos

Confirme que os arquivos existem em `C:\Users\Daniella\ti\`:
```powershell
ls C:\Users\Daniella\ti\*.ps1
```

Você deve ver:
- `data-sync-automacao.ps1`
- `agendar-datasync-admin.ps1`
- `guardar-senha-email.ps1`

### Etapa 2: Guardar Credencial de Email (UMA VEZ APENAS)

**⚠️ Execute como Administrador**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\Daniella\ti\guardar-senha-email.ps1'
```

Será solicitado:
- **Email**: `daniella@dorinhos.com.br` (já preenchido)
- **Senha**: Digite a senha do Office365

A senha será **criptografada** e guardada em `C:\Users\Daniella\ti\.email_cred`

✅ Arquivo criado com sucesso

### Etapa 3: Agendar Tarefas (UMA VEZ APENAS)

**⚠️ Execute como Administrador**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\Daniella\ti\agendar-datasync-admin.ps1'
```

Serão criadas 3 tarefas no Windows Task Scheduler:
- `DataSync_1030` → 10:30
- `DataSync_1430` → 14:30
- `DataSync_1630` → 16:30

✅ Tarefas criadas com sucesso

### Verificar Instalação

Para confirmar que tudo está funcionando:

```powershell
# Verificar tarefas agendadas
Get-ScheduledTask -TaskName DataSync_*

# Verificar credencial de email
Test-Path C:\Users\Daniella\ti\.email_cred

# Verificar pasta de logs
Test-Path C:\Logs\DataSync
```

---

## 📊 Operação e Monitoramento

### Execução Manual (Teste)

Se precisar executar a sincronização manualmente:

```powershell
# Execute como Administrador
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\Daniella\ti\data-sync-automacao.ps1'
```

**Duração esperada**: ~11-12 minutos (10 min de pausa + tempo de execução)

### Monitorar Execução

Enquanto o script está em execução:
- Você verá **notificações na tela** (msg.exe)
- **Log em tempo real** será exibido no console PowerShell

### Consultar Resultados

Após cada execução, verifique o log:

```powershell
# Log do dia atual
type C:\Logs\DataSync\sync_$(Get-Date -Format 'yyyy-MM-dd').log

# Últimas linhas do log
tail -n 20 C:\Logs\DataSync\sync_$(Get-Date -Format 'yyyy-MM-dd').log
```

### Alertas por Email

**Quando enviado**: Apenas quando há **falhas** em alguma loja

**Conteúdo do email**:
```
ALERTA DE ERRO - DATA SYNC

Data/Hora: 15/05/2026 14:35:22

RESUMO:
- Lojas com SUCESSO: 37
- Lojas com FALHA: 1

LOJAS COM ERRO:
04

Verifique o log em: C:\Logs\DataSync\sync_2026-05-15.log
```

---

## 🔧 Troubleshooting

### Problema: Script não executa

**Sintoma**: Tarefa não inicia ou erro de execução

**Solução**:
```powershell
# Verificar se a tarefa está habilitada
Get-ScheduledTask -TaskName DataSync_1030 | Select-Object State

# Recriar tarefas
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\Daniella\ti\agendar-datasync-admin.ps1'
```

### Problema: Email não chega

**Sintoma**: Falhas ocorrem mas nenhum email é enviado

**Solução**:
```powershell
# Verificar se credencial existe
Test-Path C:\Users\Daniella\ti\.email_cred

# Se não existir, recrear
powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\Daniella\ti\guardar-senha-email.ps1'

# Verificar conectividade SMTP
Test-NetConnection smtp.office365.com -Port 587
```

### Problema: Lojas falhando

**Sintoma**: Uma ou mais lojas com status ERRO

**Solução**:
1. Verifique o **log detalhado**:
   ```powershell
   type C:\Logs\DataSync\sync_$(Get-Date -Format 'yyyy-MM-dd').log | grep ERRO
   ```

2. Erros comuns:
   - **"Atalho não encontrado"** → Verificar se arquivo .lnk existe no servidor
   - **"Timeout"** → Aumentar timeout em linha 121 do script
   - **"Conexão recusada"** → Verificar conectividade com 192.168.0.147

3. Se problema persistir:
   - Testar executando manualmente a loja problemática
   - Verificar logs do Datasync no servidor

### Problema: Pausa de 10 minutos é muito longa/curta

**Solução**: Editar `data-sync-automacao.ps1` linha 193:
```powershell
Start-Sleep -Seconds 600  # Altere 600 para segundos desejados
```

Exemplos:
- `300` = 5 minutos
- `600` = 10 minutos
- `900` = 15 minutos

### Problema: Timeout em lojas específicas

**Sintoma**: Loja X sempre falha com timeout

**Solução**: Aumentar timeout em linha 121 do script:
```powershell
[int]$TimeoutSeconds = 600  # Padrão: 10 minutos
```

Altere para:
```powershell
[int]$TimeoutSeconds = 900  # 15 minutos
```

---

## 📚 Referência Técnica

### Estrutura de Log

Cada entrada segue o padrão:
```
[2026-05-15 14:30:45] [INFO] SINCRONIZANDO 38 LOJAS
[2026-05-15 14:30:46] [INFO] FASE 1: Executando RECEBE para todas as 38 lojas...
[2026-05-15 14:30:47] [INFO] Loja 03: Executando RECEBE...
[2026-05-15 14:30:58] [OK] Loja 03 - RECEBE concluido
[2026-05-15 14:40:45] [INFO] FASE 2: Executando ENVIA para todas as 38 lojas...
[2026-05-15 14:40:46] [INFO] Loja 03: Executando ENVIA...
[2026-05-15 14:40:52] [OK] Loja 03 - ENVIA concluido
[2026-05-15 14:41:15] [SUCCESS] TODAS AS LOJAS SINCRONIZADAS COM SUCESSO!
```

### Níveis de Log

| Nível | Significado | Ação |
|-------|-----------|------|
| `INFO` | Informação geral | Monitorar |
| `SUCCESS` | Operação bem-sucedida | Tudo OK |
| `WARNING` | Aviso não-crítico | Investigar |
| `ERROR` | Erro crítico | Intervir |

### Lojas Suportadas

```powershell
# IDs das 38 lojas
@(3, 4, 5, 6, 7, 9, 14, 16, 17, 21, 23, 26, 28, 29, 31, 32, 33, 34, 36, 37, 38, 40, 41, 42, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57)
```

### Variáveis de Configuração

Editar o início do `data-sync-automacao.ps1`:

```powershell
$ServidorPath = "\\192.168.0.147\Users\Datasync\Desktop\DATA SYNC SERVER"  # Caminho base
$ServidorIP = "192.168.0.147"                                              # IP do servidor
$VBSScript = "\\192.168.0.147\Users\Datasync\Desktop\executar_atalho.vbs"  # VBS remoto
$LogPath = "C:\Logs\DataSync"                                              # Pasta de logs
$EmailRemetente = "daniella@dorinhos.com.br"                               # Email de envio
$EmailDestino = "daniella@dorinhos.com.br"                                 # Email de recebimento
$SmtpServer = "smtp.office365.com"                                         # Servidor SMTP
$SmtpPort = 587                                                            # Porta SMTP
```

### Funções Disponíveis

**Log-Message**: Registra mensagens no log e console
```powershell
Log-Message "Mensagem aqui" "INFO"      # INFO, WARNING, ERROR, SUCCESS
```

**Notify-Desktop**: Mostra notificação na tela
```powershell
Notify-Desktop "Título" "Mensagem aqui"
```

**Execute-Atalho**: Executa atalho remoto
```powershell
Execute-Atalho -AtalhoPath $caminho -Loja $numero -Tipo "RECEBE" -VBSScript $vbs
```

---

## 📞 Suporte

Para problemas não resolvidos por este manual:

1. Verifique o **log completo**: `C:\Logs\DataSync\`
2. Teste **conectividade**: `ping 192.168.0.147`
3. Verifique **permissões**: Execute como Admin
4. Consulte o **código-fonte**: Comentários em `data-sync-automacao.ps1`

---

**Última atualização**: 15 de maio de 2026  
**Versão do Script**: 2.0 (Batch Execution com Email)  
**Status**: ✅ Produção

