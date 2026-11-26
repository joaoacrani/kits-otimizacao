@echo off
rem Kit Business - nao precisa de administrador. (Prefira o Kit-Business.exe da pasta dist.)
set PSModulePath=
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Kit-Business.ps1"
