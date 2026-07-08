@echo off
REM Ativar Monitor Data Sync como Serviço Windows
REM Execute como ADMINISTRADOR

echo.
echo ════════════════════════════════════════════════
echo ATIVANDO MONITOR DATA SYNC COMO WINDOWS SERVICE
echo ════════════════════════════════════════════════
echo.

REM Verificar se é administrador
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERRO: Execute como ADMINISTRADOR!
    pause
    exit /b 1
)

REM Executar script PowerShell
powershell -ExecutionPolicy Bypass -NoProfile -File "C:\Users\Datasync\Desktop\instalar-servico-datasync.ps1"

echo.
echo ════════════════════════════════════════════════
echo CONCLUIDO
echo ════════════════════════════════════════════════
pause
