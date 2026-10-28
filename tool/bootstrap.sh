#!/usr/bin/env bash
set -euo pipefail
command -v flutter >/dev/null || { echo "Install Flutter SDK first" >&2; exit 1; }
flutter doctor -v
flutter create --project-name ereader --org com.example.ereader --platforms=windows,android .
# Materialize Android MediaSession foreground-service declarations after Flutter create.
cp tool/android/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
mkdir -p android/app/src/main/kotlin/com/example/ereader/ereader
cp tool/android/MainActivity.kt android/app/src/main/kotlin/com/example/ereader/ereader/MainActivity.kt
flutter pub get
flutter analyze
flutter test
echo "Use a Windows host with Visual Studio C++ to build Windows targets."
