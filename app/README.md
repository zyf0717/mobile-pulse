# mobile_pulse

Flutter app that streams sensor data from a Polar H10 and a Polar Pacer to a relay server, alongside GPS and pulse-oximeter streams.

## Features

- **GPS** — live location stream relayed over HTTP
- **Pulse** — pulse-oximeter stream relayed over HTTP
- **Polar H10** — HR, ACC, ECG streams via the `polar` package
- **Polar Pacer** — HR, ACC, PPI streams via the `polar` package

## Setup

Copy `dart_defines.env.example` to `dart_defines.env` and fill in device IDs and relay URLs.

## Commands

```sh
# Connect tailscale device if applicable
adb tcpip 5555
adb connect 100.81.55.124:5555

# Install dependencies
flutter pub get

# Analyse
flutter analyze

# Run tests
flutter test

# Run on a connected device (with env vars)
flutter run --dart-define-from-file=dart_defines.env

# Build APK
flutter build apk --dart-define-from-file=dart_defines.env
```

