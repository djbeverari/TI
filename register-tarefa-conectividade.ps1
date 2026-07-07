$nomeTarefa = 'ConectividadeLojas'

$acao = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\Users\Daniella\ti\testa-conectividade.ps1"'

# Trigger "Once" com repetição é o jeito de expressar "a cada 5 min" no ScheduledTasks;
# copiamos a repetição pra um trigger Weekly (dias úteis) porque -Weekly não aceita
# -RepetitionInterval diretamente.
$gatilhoBase = New-ScheduledTaskTrigger -Once -At '08:00' `
    -RepetitionInterval (New-TimeSpan -Minutes 5) `
    -RepetitionDuration (New-TimeSpan -Hours 10)

$gatilho = New-ScheduledTaskTrigger -Weekly `
    -DaysOfWeek Monday, Tuesday, Wednesday, Thursday, Friday `
    -At '08:00'
$gatilho.Repetition = $gatilhoBase.Repetition

$configuracoes = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd

Unregister-ScheduledTask -TaskName $nomeTarefa -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask -TaskName $nomeTarefa `
    -Action $acao -Trigger $gatilho -Settings $configuracoes `
    -Description 'Testa conectividade (ping) das lojas a cada 5 min, 8h-18h, dias úteis' `
    -User $env:USERNAME -RunLevel Highest

Write-Host "Tarefa '$nomeTarefa' registrada. Próxima execução:"
(Get-ScheduledTask -TaskName $nomeTarefa | Get-ScheduledTaskInfo).NextRunTime
