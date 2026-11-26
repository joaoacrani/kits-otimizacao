@echo off
rem Kit Personal - PC de casa. (Prefira o Kit-Personal.exe da pasta dist.) Para todas as funcoes, use o botao "Reabrir como administrador" dentro do programa.
set PSModulePath=
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Kit-Personal.ps1"
