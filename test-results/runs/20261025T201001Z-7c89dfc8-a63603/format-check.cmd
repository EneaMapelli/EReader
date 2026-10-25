@echo off
call "C:\Users\eneam\AppData\Local\Temp\flutter\bin\dart.bat" "format" "--output=none" "--set-exit-if-changed" "lib" "test"
set "child_exit=%ERRORLEVEL%"
> "E:\GitHub\EReader\.local-test-results\20261025T201001Z-7c89dfc8-a63603\format-check.exit-code" echo %child_exit%
exit /b %child_exit%
