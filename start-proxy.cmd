@echo off
REM Startar Claude Code-proxyn (Haiku-tier -> DeepSeek V4 Flash).
REM Windows-motsvarighet till claude-code-proxy.service pa Hetzner.
REM Startas av schemalagd uppgift "claude-code-proxy"; loggen skrivs om vid varje start.
REM Startbannern innehaller pilar (U+2192). Utan detta blir stdout cp1252
REM vid omdirigering till fil och processen dor pa UnicodeEncodeError.
set PYTHONUTF8=1
set PYTHONIOENCODING=utf-8

cd /d "%~dp0"
".venv\Scripts\python.exe" "proxy.py" > "proxy.log" 2>&1
