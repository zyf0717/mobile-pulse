class AppEnvKeys {
  static const relayGpsUrl = 'RELAY_GPS_URL';
  static const relayPulseUrl = 'RELAY_PULSE_URL';
  static const relayH10HrUrl = 'RELAY_H10_HR_URL';
  static const relayH10EcgUrl = 'RELAY_H10_ECG_URL';
  static const relayH10AccUrl = 'RELAY_H10_ACC_URL';
  static const polarH10DeviceId = 'POLAR_H10_DEVICE_ID';
  static const relayPacerHrUrl = 'RELAY_PACER_HR_URL';
  static const relayPacerAccUrl = 'RELAY_PACER_ACC_URL';
  static const relayPacerPpiUrl = 'RELAY_PACER_PPI_URL';
  static const polarPacerDeviceId = 'POLAR_PACER_DEVICE_ID';
  static const polarLoopDeviceId = 'POLAR_LOOP_DEVICE_ID';
}

class AppEnv {
  static const relayGpsUrl = String.fromEnvironment(AppEnvKeys.relayGpsUrl);
  static const relayPulseUrl = String.fromEnvironment(AppEnvKeys.relayPulseUrl);
  static const relayH10HrUrl = String.fromEnvironment(AppEnvKeys.relayH10HrUrl);
  static const relayH10EcgUrl = String.fromEnvironment(
    AppEnvKeys.relayH10EcgUrl,
  );
  static const relayH10AccUrl = String.fromEnvironment(
    AppEnvKeys.relayH10AccUrl,
  );
  static const polarH10DeviceId = String.fromEnvironment(
    AppEnvKeys.polarH10DeviceId,
  );
  static const relayPacerHrUrl = String.fromEnvironment(
    AppEnvKeys.relayPacerHrUrl,
  );
  static const relayPacerAccUrl = String.fromEnvironment(
    AppEnvKeys.relayPacerAccUrl,
  );
  static const relayPacerPpiUrl = String.fromEnvironment(
    AppEnvKeys.relayPacerPpiUrl,
  );
  static const polarPacerDeviceId = String.fromEnvironment(
    AppEnvKeys.polarPacerDeviceId,
  );
  static const polarLoopDeviceId = String.fromEnvironment(
    AppEnvKeys.polarLoopDeviceId,
  );
}
