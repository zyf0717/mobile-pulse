# mobile_pulse_loop

Dedicated Flutter app for Polar Loop/360 management.

## Setup

Create `dart_defines.env` first, then set the Loop device ID.

```sh
cp dart_defines.env.example dart_defines.env
```

If you already have the Loop ID in `../app/dart_defines.env`, reuse that value here.

## Commands

```sh
flutter pub get
flutter analyze
flutter run --dart-define-from-file=dart_defines.env
flutter build apk --dart-define-from-file=dart_defines.env
```

## Exports

Loop exports are saved into Android `Downloads/Polar Loop/...` so they are user-visible. The app also exposes:

- `Export Files` to save the data file and `summary.json`
- `Export & Share` to save them and immediately open the system share sheet
