@echo off
REM Pausar Agendamentos Data Sync
REM Desabilita as 3 tasks do Task Scheduler

echo.
echo ════════════════════════════════════════════════
echo PAUSING DATA SYNC SCHEDULES
echo ════════════════════════════════════════════════
echo.

echo Desabilitando: DataSync_1030...
schtasks /change /tn "DataSync_1030" /disable

echo Desabilitando: DataSync_1430...
schtasks /change /tn "DataSync_1430" /disable

echo Desabilitando: DataSync_1630...
schtasks /change /tn "DataSync_1630" /disable

echo.
echo ════════════════════════════════════════════════
echo AGENDAMENTOS PAUSADOS
echo.
echo Para retomar, execute: retomar-agendamentos.bat
echo ════════════════════════════════════════════════
echo.
pause
