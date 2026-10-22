#!/usr/bin/env bash
set -euo pipefail
command -v flutter >/dev/null || { echo "Install Flutter SDK first" >&2; exit 1; }
flutter doctor -v
flutter create --project-name ereader --org com.example.ereader --platforms=windows,android .
flutter pub get
flutter analyze
flutter test
echo "Use a Windows host with Visual Studio C++ to build Windows targets."
