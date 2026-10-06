@echo off
:: ============================================================
:: Lançador do Otimizador Corporativo Windows 10/11
:: Solicita elevação (UAC) e executa o script PowerShell
:: ============================================================

:: Verifica se já está rodando como Administrador
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando elevacao de privilégios...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

:: Agora está como Administrador — executa o script PS1
echo.
echo ============================================================
echo  OTIMIZADOR CORPORATIVO WINDOWS 10/11
echo  Executando como Administrador...
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Optimize-WindowsCorporate.ps1"

echo.
echo ============================================================
echo  Execucao concluida. Pressione qualquer tecla para fechar.
echo ============================================================
pause >nul