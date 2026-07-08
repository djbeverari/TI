# Agendador Data Sync - Setup Automático

## 📋 Resumo
- **Script**: `C:\Users\Daniella\ti\data-sync-automacao.ps1`
- **Horários**: 10:30, 14:30, 16:30
- **Frequência**: Diária
- **Logs**: `C:\Logs\DataSync\sync_YYYY-MM-DD.log`

---

## 🔧 Setup - 3 Opções

### Opção 1: PowerShell (Automático)

Cole e execute no PowerShell como **Admin**:

```powershell
# Criar tarefa para 10:30
$Action1 = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File C:\Users\Daniella\ti\data-sync-automacao.ps1"
$Trigger1 = New-ScheduledTaskTrigger -Daily -At "10:30"
Register-ScheduledTask -TaskName "DataSync_1030" -Action $Action1 -Trigger $Trigger1 -RunLevel Highest

# Criar tarefa para 14:30
$Trigger2 = New-ScheduledTaskTrigger -Daily -At "14:30"
Register-ScheduledTask -TaskName "DataSync_1430" -Action $Action1 -Trigger $Trigger2 -RunLevel Highest

# Criar tarefa para 16:30
$Trigger3 = New-ScheduledTaskTrigger -Daily -At "16:30"
Register-ScheduledTask -TaskName "DataSync_1630" -Action $Action1 -Trigger $Trigger3 -RunLevel Highest

Write-Host "✅ 3 tarefas agendadas com sucesso!"
```

---

### Opção 2: Task Scheduler (Manual)

1. **Abrir Task Scheduler** (Agendador de Tarefas)
   - Windows + R → `taskschd.msc`

2. **Criar Nova Tarefa**:
   - Clique em "Create Task..."
   - Nome: `DataSync_1030`
   - Marque: ☑️ "Run with highest privileges"

3. **Aba "Triggers"**:
   - New → Daily → 10:30 → OK

4. **Aba "Actions"**:
   - New → Program: `C:\Windows\System32\powershell.exe`
   - Arguments: `-NoProfile -ExecutionPolicy Bypass -File C:\Users\Daniella\ti\data-sync-automacao.ps1`
   - OK

5. **Repetir para 14:30 e 16:30** (nomes: `DataSync_1430`, `DataSync_1630`)

---

### Opção 3: Batch Script (Windows)

Crie `C:\Users\Daniella\ti\agendar-tarefas.bat`:

```batch
@echo off
REM Agendador automático para Data Sync

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"^
$Action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\Users\Daniella\ti\data-sync-automacao.ps1'; ^
Register-ScheduledTask -TaskName 'DataSync_1030' -Action $Action -Trigger (New-ScheduledTaskTrigger -Daily -At '10:30') -RunLevel Highest -Force; ^
Register-ScheduledTask -TaskName 'DataSync_1430' -Action $Action -Trigger (New-ScheduledTaskTrigger -Daily -At '14:30') -RunLevel Highest -Force; ^
Register-ScheduledTask -TaskName 'DataSync_1630' -Action $Action -Trigger (New-ScheduledTaskTrigger -Daily -At '16:30') -RunLevel Highest -Force; ^
Write-Host 'Tarefas criadas com sucesso!'; ^
"

pause
```

Depois execute como Admin:
```
C:\Users\Daniella\ti\agendar-tarefas.bat
```

---

## ✅ Verificar se funcionou

**Ver tarefas criadas**:
```powershell
Get-ScheduledTask -TaskName "DataSync_*" | Select TaskName, State, Triggers
```

**Ver logs**:
```powershell
Get-Content C:\Logs\DataSync\sync_$(Get-Date -Format 'yyyy-MM-dd').log
```

---

## 📊 O que o script faz

1. ✅ Acessa `\\192.168.0.147\C$\Users\Datasync\Desktop`
2. ✅ Executa para cada loja (01 a 36):
   - Recebe_XX (sincroniza dados)
   - Aguarda 5 segundos
   - Envia_XX (envia atualizações)
3. ✅ Se falhar: Notifica no desktop
4. ✅ Registra tudo em log diário

---

## 🐛 Troubleshooting

| Erro | Solução |
|------|---------|
| "Access Denied" | Executar PowerShell como **Admin** |
| Atalho não encontrado | Verificar caminho: `\\192.168.0.147\C$\Users\Datasync\Desktop` |
| Tarefa não executa | Verificar se executou script corretamente |
| Sem notificação | Checar se explorer.exe está rodando |

---

## 🔄 Testar manualmente

Executar script agora (sem agendar):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Daniella\ti\data-sync-automacao.ps1
```

