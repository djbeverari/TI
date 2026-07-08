# Teste Data Sync - Segunda-Feira (2026-05-19)

## Status Atual
✅ Script foi corrigido e está pronto para testar
- Localização: `C:\Users\Daniella\ti\data-sync-automacao.ps1`
- Método: WScript.Shell para ler atalhos + Start-Process -NoNewWindow
- Funciona rodando diretamente no servidor

## Passos para Testar Segunda-Feira

### 1. Copiar Script para Servidor
```powershell
Copy-Item "C:\Users\Daniella\ti\data-sync-automacao.ps1" -Destination "\\192.168.0.147\Users\Datasync\Desktop\" -Force
```

### 2. Conectar ao Servidor via Radmin
- Usar Radmin para acessar o servidor 192.168.0.147

### 3. Executar o Script
No PowerShell do servidor:
```powershell
& "C:\Users\Datasync\Desktop\data-sync-automacao.ps1"
```

### 4. Acompanhar Execução
Em outro PowerShell do servidor (ou sua máquina):
```powershell
Get-Content "C:\Logs\DataSync\sync_$(Get-Date -Format 'yyyy-MM-dd').log" -Wait -Tail 20
```

## O Que Esperar

**Fase 1 (RECEBE)**: ~3-5 minutos
- Mensagens: "Loja XX: Executando RECEBE..."
- Deve processar todas as 38 lojas

**Pausa**: 10 minutos
- Mensagem: "AGUARDANDO 10 MINUTOS antes de ENVIAR..."

**Fase 2 (ENVIA)**: ~3-5 minutos
- Mensagens: "Loja XX: Executando ENVIA..."
- Deve processar todas as 38 lojas

**Resumo Final**:
- "[OK] Lojas com sucesso: 38"
- "[ERRO] Lojas com falha: 0"
- "[SUCESSO] TODAS AS LOJAS SINCRONIZADAS COM SUCESSO!"

## Se Funcionar ✅
1. Copiar script para ambos os horários restantes (se não estiver agendado)
2. Agendar no Windows Task Scheduler (10:30, 14:30, 16:30)
3. Depois adicionar notificações por email

## Se Tiver Erro ❌
1. Copiar o log completo
2. Enviar para análise
3. Verificar se todos os atalhos existem no servidor:
   - `\\192.168.0.147\Users\Datasync\Desktop\DATA SYNC SERVER\RECEBER\RECEBE LOJA XX.lnk`
   - `\\192.168.0.147\Users\Datasync\Desktop\DATA SYNC SERVER\ENVIAR\ENVIA LOJA XX.lnk`

---
**Última atualização**: 2026-05-15
**Próximo teste**: 2026-05-19 (segunda-feira)
