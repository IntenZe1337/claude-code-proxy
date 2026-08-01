@echo off
REM Startar Claude Code-proxyn (Haiku-tier -> DeepSeek V4 Flash).
REM Windows-motsvarighet till claude-code-proxy.service pa Hetzner.
REM Startas av schemalagd uppgift "claude-code-proxy"; loggen appendas (inte
REM skrivs om) sedan 2026-08-01 så proxy-usage-rapporten inte tappar data vid
REM omstart. Loggen växer; ingen rotation än — övervakas via disk-grinden.
REM Startbannern innehaller pilar (U+2192). Utan detta blir stdout cp1252
REM vid omdirigering till fil och processen dor pa UnicodeEncodeError.
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

cd /d "%~dp0"

REM Stop-ScheduledTask dodar cmd-wrappern men inte det detacherade python-barnet.
REM En kvarvarande lyssnare gor att den nya instansen inte kan binda porten och dor
REM tyst, medan den gamla fortsatter svara med FORALDRAD konfiguration (t.ex. gammal
REM modell i .env). Vi kor i taskens egen session 0-kontext och far darfor doda den.
REM Bada filtren behovs: LISTENING-raderna har foreign address 0.0.0.0:0, sa ":8082 "
REM kan da bara matcha lokal adress - annars hade etablerade klientanslutningar
REM MOT proxyn matchat och vi hade dodat anroparen i stallet.
for /f "tokens=5" %%p in ('netstat -ano ^| findstr /c:"LISTENING" ^| findstr /c:":8082 "') do (
    echo Dodar kvarvarande lyssnare pa 8082: PID %%p
    taskkill /F /PID %%p >nul 2>&1
)
ping -n 3 127.0.0.1 >nul

".venv\Scripts\python.exe" "proxy.py" >> "proxy.log" 2>&1
