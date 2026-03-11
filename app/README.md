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
POLAR_PACER_DEVICE_ID
RELAY_GPS_URL
RELAY_PULSE_URL
RELAY_H10_HR_URL
RELAY_H10_ECG_URL
RELAY_H10_ACC_URL
RELAY_PACER_HR_URL
RELAY_PACER_ACC_URL
RELAY_PACER_PPI_URL
```

Polar Pacer support depends on Polar's watch SDK-sharing flow. Per Polar's
official docs, the watch must be paired to this phone, `SDK -> Share` must be
enabled on the watch, and streaming is only available from an exercise wait
screen.
