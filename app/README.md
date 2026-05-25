# Polar Streams

Flutter app that streams sensor data from a Polar H10 and a Polar Pacer to a relay server, alongside GPS and pulse-oximeter streams.

Polar Loop/360 support has been split into the separate `../loop_app` Flutter app so it runs in a different Android process and no longer shares the Polar SDK instance with Pacer/H10 work.

## Features

- **GPS** — live location stream relayed over HTTP
- **Pulse** — pulse-oximeter stream relayed over HTTP
- **Polar H10** — HR, ACC, ECG streams via the `polar` package
- **Polar Pacer** — HR, ACC, PPI streams via the `polar` package

## Setup

Copy `dart_defines.env.example` to `dart_defines.env` and fill in device IDs and relay URLs.

## Loop App

Polar Loop/360 now runs from the separate `../loop_app` app.

```sh
cd ../loop_app

# First-time setup
cp dart_defines.env.example dart_defines.env

# Set the Loop device ID in dart_defines.env, then run:
flutter pub get
flutter analyze
flutter run --dart-define-from-file=dart_defines.env
```

## Commands

```sh
# Connect tailscale device if applicable; port depends on android device, may not be 5555
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
