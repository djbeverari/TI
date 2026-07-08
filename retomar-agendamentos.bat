@echo off
REM Retomar Agendamentos Data Sync
REM Habilita as 3 tasks do Task Scheduler

echo.
echo ════════════════════════════════════════════════
echo RESUMING DATA SYNC SCHEDULES
echo ════════════════════════════════════════════════
echo.

echo Habilitando: DataSync_1030...
schtasks /change /tn "DataSync_1030" /enable

echo Habilitando: DataSync_1430...
schtasks /change /tn "DataSync_1430" /enable

echo Habilitando: DataSync_1630...
schtasks /change /tn "DataSync_1630" /enable

echo.
echo ════════════════════════════════════════════════
echo AGENDAMENTOS RETOMADOS
echo.
echo Proximas execucoes:
echo  - 10:30
echo  - 14:30
echo  - 16:30
echo ════════════════════════════════════════════════
echo.
pause
