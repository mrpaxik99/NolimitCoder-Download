@echo off
REM NolimitCoder-Download auto-publish — spusti po prihlaseni, skryte na pozadi.
REM Prikaz publish.ps1 hlida dist/ a po novem buildu pushne instalator
REM na github.com/mrpaxik99/NolimitCoder-Download (jediny zdroj pravdy pro verze).
start "" /min powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "D:\DEVELOPER\Download New Version\publish.ps1"
exit