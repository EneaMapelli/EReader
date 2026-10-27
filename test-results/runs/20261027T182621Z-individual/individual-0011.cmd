@echo off
call "C:\Users\eneam\AppData\Local\Temp\flutter\bin\flutter.bat" "test" "--reporter" "json" "--no-pub" "test/audio/openai_speech_engine_test.dart"
set "child_exit=%ERRORLEVEL%"
> "E:\GitHub\EReader\.local-test-results\20261027T181350Z-6c269f0e-e93cb6\individual-0011.exit-code" echo %child_exit%
exit /b %child_exit%
