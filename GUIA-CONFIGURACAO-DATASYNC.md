# 📋 GUIA DE CONFIGURAÇÃO - DATA SYNC AUTOMAÇÃO

**Data:** 2026-05-19  
**Versão:** 1.0  
**Status:** Pronto para configuração

---

## ✅ CHECKLIST DE CONFIGURAÇÃO

### FASE 1: ATIVAR MONITORAMENTO COMO SERVIÇO WINDOWS

**⏱️ Tempo estimado:** 5 minutos

#### Passo 1.1: Abrir PowerShell como ADMINISTRADOR

1. Clique em **Iniciar** (Windows)
2. Digite: `PowerShell`
3. Clique com **botão direito** em "Windows PowerShell"
4. Selecione: **"Executar como administrador"**
5. Clique em **"Sim"** na confirmação de controle de acesso

#### Passo 1.2: Navegar até a pasta do servidor

Na janela PowerShell, digite:
```powershell
cd C:\Users\Datasync\Desktop
```

Pressione **Enter**

#### Passo 1.3: Executar o script de instalação

Digite:
```powershell
& '.\ativar-monitoramento.bat'
```

Pressione **Enter**

**Espere a mensagem de conclusão:**
```
✅ SERVIÇO CRIADO E INICIADO COM SUCESSO!
```

**✅ Se vir esta mensagem, o monitor está rodando como serviço Windows!**

---

### FASE 2: INICIAR GERADOR DO PAINEL WEB

**⏱️ Tempo estimado:** 3 minutos

#### Passo 2.1: Abrir novo PowerShell como ADMINISTRADOR

1. Abra outro PowerShell como admin (mesmo processo do Passo 1.1)

#### Passo 2.2: Navegar até a pasta

Digite:
```powershell
cd C:\Users\Datasync\Desktop
```

Pressione **Enter**

#### Passo 2.3: Executar gerador do painel

Digite:
```powershell
& '.\gerar-painel-datasync.ps1'
```

Pressione **Enter**

**Espere a mensagem:**
```
✅ Painel atualizado: C:\Logs\DataSync\painel.html
```

**⚠️ IMPORTANTE:** Deixe esta janela PowerShell ABERTA. O painel atualiza a cada 30 segundos enquanto rodando.

Se quiser fechar depois, use **Ctrl+C** para parar.

---

### FASE 3: ACESSAR O PAINEL WEB

**⏱️ Tempo estimado:** 2 minutos

#### Passo 3.1: De qualquer máquina da rede

Abra o **Explorador de Arquivos** (Windows):

1. Pressione **Windows + E**

#### Passo 3.2: Acessar compartilhamento

Na barra de endereço (topo), cole:
```
\\192.168.0.147\Logs\DataSync
```

Pressione **Enter**

#### Passo 3.3: Abrir painel no navegador

1. Clique no arquivo: `painel.html`
2. Ou **duplo-clique** para abrir no navegador padrão

**Você verá o painel com:**
- ✅ Status geral (ATIVO)
- ✅ Lojas com sucesso
- ✅ Lojas com falha
- ✅ Lista de lojas com erros
- ✅ Informações do sistema
- ✅ Auto-atualiza a cada 30 segundos

---

## 🎯 COMMANDS ÚTEIS (Para referência)

### Parar/Iniciar o Monitor

**Parar o monitoramento:**
```powershell
Stop-Service -Name "DataSyncMonitor"
```

**Iniciar o monitoramento:**
```powershell
Start-Service -Name "DataSyncMonitor"
```

**Ver status:**
```powershell
Get-Service -Name "DataSyncMonitor"
```

### Pausar/Retomar Execuções Agendadas

**Pausar as 3 execuções (10:30, 14:30, 16:30):**
```powershell
& 'C:\Users\Datasync\Desktop\pausar-agendamentos.ps1'
```

**Retomar as execuções:**
```powershell
& 'C:\Users\Datasync\Desktop\retomar-agendamentos.ps1'
```

### Executar Sincronização Manualmente

```cmd
C:\Users\Datasync\Desktop\executar-datasync.bat
```

---

## 📊 O QUE ACONTECE AGORA

### Horários de Execução Automática (Seg-Sex)

| Horário | Ação |
|---------|------|
| **10:30** | Executa: RECEBE todas as lojas → Pausa 10min → ENVIA todas as lojas |
| **14:30** | Repete o mesmo processo |
| **16:30** | Repete o mesmo processo |

### Monitoramento

- ✅ Monitor roda **24/7** detectando erros
- ✅ Quando houver erro, salva em `alertas_YYYY-MM-DD.log`
- ✅ Painel web atualiza em **tempo real**

### Alertas de Falha

**PRIMEIRA FALHA da loja:** ⚠️  
- Monitor registra para acompanhamento

**SEGUNDA FALHA da mesma loja:** 🔴  
- ALERTA CRÍTICO - Investigar imediatamente

**TERCEIRA FALHA:** 🔴🔴  
- ALERTA CRÍTICO - Ação imediata necessária

---

## 🆘 TROUBLESHOOTING

### Problema: "Acesso negado" ao executar script

**Solução:** Execute PowerShell como ADMINISTRADOR
1. Botão direito em PowerShell
2. "Executar como administrador"
3. Clique "Sim"

### Problema: Painel não atualiza

**Solução:** 
1. Verifique se gerar-painel-datasync.ps1 está rodando
2. Atualize o navegador (F5)
3. Limpe cache (Ctrl+Shift+Delete)

### Problema: Não consigo acessar \\192.168.0.147\Logs\DataSync

**Solução:**
1. Verifique se o servidor está ligado
2. Verifique conectividade de rede (ping 192.168.0.147)
3. Verifique permissões de compartilhamento

### Problema: Monitor não detecta erros

**Solução:**
1. Verifique se serviço DataSyncMonitor está rodando: `Get-Service -Name DataSyncMonitor`
2. Verifique se sync_YYYY-MM-DD.log foi criado
3. Aguarde próxima execução agendada (10:30, 14:30, 16:30)

---

## ✅ CONCLUSÃO

Depois de seguir todos os passos:

- 🟢 Monitor está rodando como Windows Service (24/7)
- 🟢 Painel web está acessível na rede
- 🟢 Sincronizações rodando nos horários agendados
- 🟢 Alertas acionáveis quando houver falha
- 🟢 Histórico salvo em arquivo de alertas

**Sistema completo e operacional! 🎉**

---

## 📞 SUPORTE

Se houver dúvidas ou problemas:
1. Verifique este guia (seção Troubleshooting)
2. Verifique logs em `C:\Logs\DataSync\`
3. Contate: agente@dorinhos.com.br

---

**Última atualização:** 2026-05-19
