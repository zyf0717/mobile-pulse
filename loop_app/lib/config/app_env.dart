class AppEnvKeys {
  static const polarLoopDeviceId = 'POLAR_LOOP_DEVICE_ID';
}

class AppEnv {
  static const polarLoopDeviceId = String.fromEnvironment(
    AppEnvKeys.polarLoopDeviceId,
  );
}
