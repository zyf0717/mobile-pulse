# mobile_pulse

Runtime configuration is provided through compile-time Dart defines in
`dart_defines.env`.

Run the app with:

```bash
flutter run --dart-define-from-file=dart_defines.env
```

Current keys:

```text
POLAR_H10_DEVICE_ID
RELAY_GPS_URL
RELAY_PULSE_URL
RELAY_H10_HR_URL
RELAY_H10_ECG_URL
RELAY_H10_ACC_URL
```
