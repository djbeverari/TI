---
name: data-sync-automacao
description: Automação de sincronização Data Sync (PowerShell) - 38 lojas específicas
metadata:
  type: reference
---

# Data Sync - Automação

## Problema
Clicar manualmente Recebe + Envia para 38 lojas específicas, 3x/dia (76 cliques!).

## Solução
Script PowerShell que executa **Recebe_XX → Envia_XX** para as 38 lojas automaticamente, 3x/dia (10:30, 14:30, 16:30).

---

## Lojas Sincronizadas (38 no total)
03, 04, 05, 06, 07, 09, 14, 16, 17, 21, 23, 26, 28, 29, 31, 32, 33, 34, 36, 37, 38, 40, 41, 42, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57

---

## Arquitetura

| Componente | Localização |
|-----------|------------|
| Script principal | `C:\Users\Daniella\ti\data-sync-automacao.ps1` |
| Atalhos Recebe | `\\192.168.0.147\C$\Users\Datasync\Desktop\Recebe_03.lnk` até `Recebe_57.lnk` |
| Atalhos Envia | `\\192.168.0.147\C$\Users\Datasync\Desktop\Envia_03.lnk` até `Envia_57.lnk` |
| Logs | `C:\Logs\DataSync\sync_YYYY-MM-DD.log` |
| Tarefas agendadas | Task Scheduler (3 tarefas diárias) |

---

## Fluxo

```
10:30 → Script inicia (38 lojas)
  ├─ Recebe_03 → (5s) → Envia_03
  ├─ Recebe_04 → (5s) → Envia_04
  ├─ ...
  └─ Recebe_57 → (5s) → Envia_57
  → Se alguma falhar: Notifica desktop
  → Registra logs com resumo (sucesso/falha)

14:30 → Repetir
16:30 → Repetir
```

---

## Setup Rápido

**Executar como Admin no PowerShell**:

```powershell
$Action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\Users\Daniella\ti\data-sync-automacao.ps1"

Register-ScheduledTask -TaskName "DataSync_1030" -Action $Action `
  -Trigger (New-ScheduledTaskTrigger -Daily -At "10:30") -RunLevel Highest -Force

Register-ScheduledTask -TaskName "DataSync_1430" -Action $Action `
  -Trigger (New-ScheduledTaskTrigger -Daily -At "14:30") -RunLevel Highest -Force

Register-ScheduledTask -TaskName "DataSync_1630" -Action $Action `
  -Trigger (New-ScheduledTaskTrigger -Daily -At "16:30") -RunLevel Highest -Force
```

---

## Verificar Status

```powershell
# Ver tarefas
Get-ScheduledTask -TaskName "DataSync_*"

# Ver logs do dia
Get-Content C:\Logs\DataSync\sync_$(Get-Date -Format 'yyyy-MM-dd').log

# Testar agora
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Daniella\ti\data-sync-automacao.ps1
```

---

## Recursos

- **Ordem por loja**: SEMPRE Recebe_XX → (5s) → Envia_XX
- **Timeout**: 10 minutos por atalho
- **Notificações**: Desktop se falhar
- **Logs**: Um arquivo por dia com resumo (38 lojas OK ou quais falharam)
- **Pausa**: 5 segundos entre Recebe e Envia

---

## Ajustes Comuns

**Mudar lojas sincronizadas**:
```powershell
$Lojas = @(3, 4, 5, ...)  # Edite array
```

**Mudar tempo de espera entre Recebe/Envia**:
```powershell
Start-Sleep -Seconds 5  # Mude 5 para outro valor
```

**Mudar horários**:
No Task Scheduler, edite o Trigger de cada tarefa.

**Aumentar timeout**:
```powershell
[int]$TimeoutSeconds = 900  # 15 minutos em vez de 10
```
