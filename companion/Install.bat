@echo off
rem Forever Chronicler installer: finds WoW: Forever and installs the addon.
cd /d "%~dp0"
set "PY="
where py >nul 2>nul && set "PY=py -3"
if not defined PY where python >nul 2>nul && set "PY=python"
if not defined PY (
  echo Python 3 is needed. Get it from https://www.python.org/downloads/
  echo and tick "Add python.exe to PATH" during setup. Then run this again.
  pause
  exit /b 1
)
%PY% fcompanion.py install
pause
