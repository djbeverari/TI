@echo off
REM Executar Data Sync - Avulso/Manual
REM Executa no servidor 192.168.0.147

echo.
echo ════════════════════════════════════════
echo 🚀 DATA SYNC - EXECUÇÃO MANUAL
echo ════════════════════════════════════════
echo.

REM Executar script no servidor
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Datasync\Desktop\ti\data-sync-automacao.ps1"

echo.
echo ✅ Execução concluída
echo.
pause
