$ErrorActionPreference = "Stop"
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter SDK missing. Install Flutter and Visual Studio C++ Desktop workload."
}
flutter doctor -v
flutter create --project-name ereader --org com.example.ereader --platforms=windows,android .
if ($LASTEXITCODE -ne 0) { throw "flutter create failed" }
# Apply audio_service declarations to generated Android project.
Copy-Item -LiteralPath "tool/android/AndroidManifest.xml" -Destination "android/app/src/main/AndroidManifest.xml" -Force
$androidActivity = "android/app/src/main/kotlin/com/example/ereader/ereader/MainActivity.kt"
New-Item -ItemType Directory -Force -Path (Split-Path $androidActivity) | Out-Null
Copy-Item -LiteralPath "tool/android/MainActivity.kt" -Destination $androidActivity -Force
flutter pub get
flutter analyze
flutter test
Write-Host "Windows: flutter run -d windows / flutter build windows"
Write-Host "Android: flutter run -d <device-id> / flutter build apk"
