@echo off
title Painel de Conectividade das Lojas
start "" powershell -NoProfile -File "C:\Users\Daniella\ti\start-painel-http.ps1"
timeout /t 2 /nobreak >nul
start "" http://localhost:8081/conectividade.html
