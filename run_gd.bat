@echo off
"%~dp0..\tools\lua\lua.exe" "%~dp0scripts\run_moba_role_gd.lua" %*
exit /b %errorlevel%
