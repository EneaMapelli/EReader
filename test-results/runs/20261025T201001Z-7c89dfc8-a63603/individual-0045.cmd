@echo off
call "C:\Users\eneam\AppData\Local\Temp\flutter\bin\flutter.bat" "test" "--reporter" "json" "--no-pub" "test/domain/character_candidate_test.dart"
set "child_exit=%ERRORLEVEL%"
> "E:\GitHub\EReader\.local-test-results\20261025T201001Z-7c89dfc8-a63603\individual-0045.exit-code" echo %child_exit%
exit /b %child_exit%
