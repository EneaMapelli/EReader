$ErrorActionPreference = "Stop"
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter SDK missing. Install Flutter and Visual Studio C++ Desktop workload."
}
flutter doctor -v
flutter create --project-name ereader --org com.example.ereader --platforms=windows,android .
flutter pub get
flutter analyze
flutter test
Write-Host "Windows: flutter run -d windows / flutter build windows"
Write-Host "Android: flutter run -d <device-id> / flutter build apk"
