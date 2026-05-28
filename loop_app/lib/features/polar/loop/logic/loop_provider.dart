import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/app_env.dart';
import '../../common/models/polar_connection_state.dart';
import '../models/loop_models.dart';
import 'loop_service.dart';

class LoopState {
  final bool isConfigured;
  final PolarConnectionState connectionState;
  final String? lastError;
  final LoopDeviceTime? deviceTime;
  final LoopSdkModeStatus? sdkModeStatus;
  final Map<String, Object?>? diskSpace;
  final Map<String, Object?>? userDeviceSettings;
  final LoopBackendSyncPayload? lastSyncPayload;
  final LoopSnapshotExport? lastSnapshotExport;
  final Set<LoopOfflineDataType> availableOfflineDataTypes;
  final Set<LoopOfflineDataType> activeOfflineRecordingTypes;
  final Map<LoopOfflineDataType, LoopSensorSettings> normalSettingsByType;
  final Map<LoopOfflineDataType, LoopSensorSettings> fullSettingsByType;
  final List<LoopOfflineRecordingEntry> recordings;
  final Map<String, LoopDownloadProgress> downloadProgressByPath;
  final Map<String, LoopDownloadedRecord> downloadsByPath;
  final Map<String, LoopExportedRecord> exportsByPath;

  const LoopState({
    this.isConfigured = false,
    this.connectionState = PolarConnectionState.disconnected,
    this.lastError,
    this.deviceTime,
    this.sdkModeStatus,
    this.diskSpace,
    this.userDeviceSettings,
    this.lastSyncPayload,
    this.lastSnapshotExport,
    this.availableOfflineDataTypes = const {},
    this.activeOfflineRecordingTypes = const {},
    this.normalSettingsByType = const {},
    this.fullSettingsByType = const {},
    this.recordings = const [],
    this.downloadProgressByPath = const {},
    this.downloadsByPath = const {},
    this.exportsByPath = const {},
  });

  LoopCollectionMode get collectionMode =>
      sdkModeStatus?.collectionMode ?? LoopCollectionMode.unknown;

  bool get isSdkMode => sdkModeStatus?.enabled ?? false;

  LoopState copyWith({
    bool? isConfigured,
    PolarConnectionState? connectionState,
    String? lastError,
    bool? clearLastError,
    LoopDeviceTime? deviceTime,
    LoopSdkModeStatus? sdkModeStatus,
    bool? clearSdkModeStatus,
    Map<String, Object?>? diskSpace,
    bool? clearDiskSpace,
    Map<String, Object?>? userDeviceSettings,
    bool? clearUserDeviceSettings,
    LoopBackendSyncPayload? lastSyncPayload,
    bool? clearLastSyncPayload,
    LoopSnapshotExport? lastSnapshotExport,
    bool? clearLastSnapshotExport,
    Set<LoopOfflineDataType>? availableOfflineDataTypes,
    Set<LoopOfflineDataType>? activeOfflineRecordingTypes,
    Map<LoopOfflineDataType, LoopSensorSettings>? normalSettingsByType,
    Map<LoopOfflineDataType, LoopSensorSettings>? fullSettingsByType,
    List<LoopOfflineRecordingEntry>? recordings,
    Map<String, LoopDownloadProgress>? downloadProgressByPath,
    Map<String, LoopDownloadedRecord>? downloadsByPath,
    Map<String, LoopExportedRecord>? exportsByPath,
  }) => LoopState(
    isConfigured: isConfigured ?? this.isConfigured,
    connectionState: connectionState ?? this.connectionState,
    lastError: clearLastError == true ? null : (lastError ?? this.lastError),
    deviceTime: deviceTime ?? this.deviceTime,
    sdkModeStatus: clearSdkModeStatus == true
        ? null
        : (sdkModeStatus ?? this.sdkModeStatus),
    diskSpace: clearDiskSpace == true ? null : (diskSpace ?? this.diskSpace),
    userDeviceSettings: clearUserDeviceSettings == true
        ? null
        : (userDeviceSettings ?? this.userDeviceSettings),
    lastSyncPayload: clearLastSyncPayload == true
        ? null
        : (lastSyncPayload ?? this.lastSyncPayload),
    lastSnapshotExport: clearLastSnapshotExport == true
        ? null
        : (lastSnapshotExport ?? this.lastSnapshotExport),
    availableOfflineDataTypes:
        availableOfflineDataTypes ?? this.availableOfflineDataTypes,
    activeOfflineRecordingTypes:
        activeOfflineRecordingTypes ?? this.activeOfflineRecordingTypes,
    normalSettingsByType: normalSettingsByType ?? this.normalSettingsByType,
    fullSettingsByType: fullSettingsByType ?? this.fullSettingsByType,
    recordings: recordings ?? this.recordings,
    downloadProgressByPath:
        downloadProgressByPath ?? this.downloadProgressByPath,
    downloadsByPath: downloadsByPath ?? this.downloadsByPath,
    exportsByPath: exportsByPath ?? this.exportsByPath,
  );
}

class LoopNotifier extends Notifier<LoopState> {
  @override
  LoopState build() {
    final loop = ref.watch(polarLoopServiceProvider);

    final connSub = loop.connectionState.listen((connectionState) {
      final isConnected = connectionState == PolarConnectionState.connected;
      state = state.copyWith(
        connectionState: connectionState,
        clearSdkModeStatus: !isConnected,
        clearDiskSpace: !isConnected,
        clearUserDeviceSettings: !isConnected,
        clearLastSyncPayload: !isConnected,
        clearLastSnapshotExport: !isConnected,
        activeOfflineRecordingTypes: isConnected
            ? state.activeOfflineRecordingTypes
            : const {},
        downloadProgressByPath: isConnected
            ? state.downloadProgressByPath
            : const {},
        recordings: isConnected ? state.recordings : const [],
        downloadsByPath: isConnected ? state.downloadsByPath : const {},
        exportsByPath: isConnected ? state.exportsByPath : const {},
      );
    });
    final errorSub = loop.errorStream.listen((error) {
      state = state.copyWith(lastError: error.message);
    });
    final progressSub = loop.downloadProgressStream.listen((progress) {
      final nextProgress = Map<String, LoopDownloadProgress>.from(
        state.downloadProgressByPath,
      )..[progress.path] = progress;
      state = state.copyWith(downloadProgressByPath: nextProgress);
    });

    ref.onDispose(() {
      connSub.cancel();
      errorSub.cancel();
      progressSub.cancel();
      loop.dispose();
    });

    return LoopState(isConfigured: loop.isConfigured);
  }

  Future<void> connect() async {
    if (!state.isConfigured) return;
    await _run(() => ref.read(polarLoopServiceProvider).connect());
  }

  Future<void> disconnect() async {
    await _run(() => ref.read(polarLoopServiceProvider).disconnect());
  }

  Future<LoopDeviceTime?> getDeviceTime() async {
    return _runWithValue(() async {
      final value = await ref.read(polarLoopServiceProvider).getDeviceTime();
      state = state.copyWith(deviceTime: value, clearLastError: true);
      return value;
    });
  }

  Future<LoopDeviceTime?> setDeviceTime([DateTime? dateTime]) async {
    return _runWithValue(() async {
      final value = await ref
          .read(polarLoopServiceProvider)
          .setDeviceTime(dateTime ?? DateTime.now());
      state = state.copyWith(deviceTime: value, clearLastError: true);
      return value;
    });
  }

  Future<LoopSdkModeStatus?> refreshSdkModeStatus() async {
    return _runWithValue(() async {
      final status = await ref
          .read(polarLoopServiceProvider)
          .getSdkModeStatus();
      state = state.copyWith(sdkModeStatus: status, clearLastError: true);
      return status;
    });
  }

  Future<LoopSdkModeStatus?> enableSdkMode() async {
    return _runWithValue(() async {
      final status = await ref
          .read(polarLoopServiceProvider)
          .setSdkModeEnabled(true);
      state = state.copyWith(sdkModeStatus: status, clearLastError: true);
      return status;
    });
  }

  Future<LoopSdkModeStatus?> disableSdkMode() async {
    return _runWithValue(() async {
      final status = await ref
          .read(polarLoopServiceProvider)
          .setSdkModeEnabled(false);
      state = state.copyWith(sdkModeStatus: status, clearLastError: true);
      return status;
    });
  }

  Future<Map<String, Object?>?> refreshDiskSpace() async {
    return _runWithValue(() async {
      final diskSpace = await ref.read(polarLoopServiceProvider).getDiskSpace();
      state = state.copyWith(diskSpace: diskSpace, clearLastError: true);
      return diskSpace;
    });
  }

  Future<Map<String, Object?>?> refreshUserDeviceSettings() async {
    return _runWithValue(() async {
      final settings = await ref
          .read(polarLoopServiceProvider)
          .getUserDeviceSettings();
      state = state.copyWith(
        userDeviceSettings: settings,
        clearLastError: true,
      );
      return settings;
    });
  }

  Future<void> refreshDeviceContext() async {
    await _run(() async {
      await refreshSdkModeStatus();
      await refreshDiskSpace();
      await refreshUserDeviceSettings();
      state = state.copyWith(clearLastError: true);
    });
  }

  Future<LoopBackendSyncPayload?> buildSyncPayload({
    DateTime? fromDate,
    DateTime? toDate,
    List<String>? recordingPaths,
  }) async {
    return _runWithValue(() async {
      final payload = await ref
          .read(polarLoopServiceProvider)
          .buildSyncPayload(
            fromDate:
                fromDate ?? DateTime.now().subtract(const Duration(days: 2)),
            toDate: toDate ?? DateTime.now(),
            recordingPaths:
                recordingPaths ??
                state.recordings.map((entry) => entry.path).toList(),
          );
      state = state.copyWith(
        lastSyncPayload: payload,
        sdkModeStatus: payload.sdkModeStatus,
        clearLastError: true,
      );
      return payload;
    });
  }

  Future<LoopSnapshotExport?> exportNormalModeSnapshot({
    DateTime? fromDate,
    DateTime? toDate,
    List<String>? recordingPaths,
  }) async {
    return _runWithValue(() async {
      final snapshot = await ref
          .read(polarLoopServiceProvider)
          .exportNormalModeSnapshot(
            fromDate:
                fromDate ?? DateTime.now().subtract(const Duration(days: 365)),
            toDate: toDate ?? DateTime.now(),
            recordingPaths: recordingPaths,
          );
      state = state.copyWith(
        lastSnapshotExport: snapshot,
        lastSyncPayload: snapshot.payload,
        sdkModeStatus: snapshot.payload.sdkModeStatus,
        clearLastError: true,
      );
      return snapshot;
    });
  }

  Future<Set<LoopOfflineDataType>?> fetchAvailableOfflineDataTypes() async {
    return _runWithValue(() async {
      final types = await ref
          .read(polarLoopServiceProvider)
          .getAvailableOfflineDataTypes();
      state = state.copyWith(
        availableOfflineDataTypes: types,
        clearLastError: true,
      );
      return types;
    });
  }

  Future<LoopSensorSettings?> requestOfflineRecordingSettings(
    LoopOfflineDataType dataType,
  ) async {
    return _runWithValue(() async {
      final settings = await ref
          .read(polarLoopServiceProvider)
          .requestOfflineRecordingSettings(dataType);
      final next = Map<LoopOfflineDataType, LoopSensorSettings>.from(
        state.normalSettingsByType,
      )..[dataType] = settings;
      state = state.copyWith(normalSettingsByType: next, clearLastError: true);
      return settings;
    });
  }

  Future<LoopSensorSettings?> requestFullOfflineRecordingSettings(
    LoopOfflineDataType dataType,
  ) async {
    return _runWithValue(() async {
      final settings = await ref
          .read(polarLoopServiceProvider)
          .requestFullOfflineRecordingSettings(dataType);
      final next = Map<LoopOfflineDataType, LoopSensorSettings>.from(
        state.fullSettingsByType,
      )..[dataType] = settings;
      state = state.copyWith(fullSettingsByType: next, clearLastError: true);
      return settings;
    });
  }

  Future<Set<LoopOfflineDataType>?> refreshOfflineRecordingStatus() async {
    return _runWithValue(() async {
      final activeTypes = await ref
          .read(polarLoopServiceProvider)
          .getActiveOfflineRecordingTypes();
      state = state.copyWith(
        activeOfflineRecordingTypes: activeTypes,
        clearLastError: true,
      );
      return activeTypes;
    });
  }

  Future<void> startOfflineRecording(
    LoopOfflineDataType dataType, {
    Map<LoopSensorSettingType, int>? selectedSettings,
  }) async {
    await _run(() async {
      await ref
          .read(polarLoopServiceProvider)
          .startOfflineRecording(dataType, selectedSettings: selectedSettings);
      await refreshOfflineRecordingStatus();
      state = state.copyWith(clearLastError: true);
    });
  }

  Future<void> stopOfflineRecording(LoopOfflineDataType dataType) async {
    await _run(() async {
      await ref.read(polarLoopServiceProvider).stopOfflineRecording(dataType);
      await refreshOfflineRecordingStatus();
      state = state.copyWith(clearLastError: true);
    });
  }

  Future<List<LoopOfflineRecordingEntry>?> listOfflineRecordings() async {
    return _runWithValue(() async {
      final recordings = await ref
          .read(polarLoopServiceProvider)
          .listOfflineRecordings();
      state = state.copyWith(recordings: recordings, clearLastError: true);
      return recordings;
    });
  }

  Future<LoopDownloadedRecord?> downloadOfflineRecord(String path) async {
    return _runWithValue(() async {
      final record = await ref
          .read(polarLoopServiceProvider)
          .downloadOfflineRecord(path);
      final nextDownloads = Map<String, LoopDownloadedRecord>.from(
        state.downloadsByPath,
      )..[path] = record;
      final nextProgress = Map<String, LoopDownloadProgress>.from(
        state.downloadProgressByPath,
      )..remove(path);
      state = state.copyWith(
        downloadsByPath: nextDownloads,
        downloadProgressByPath: nextProgress,
        clearLastError: true,
      );
      return record;
    });
  }

  Future<LoopExportedRecord?> exportOfflineRecord(String path) async {
    return _runWithValue(() async {
      final record = await ref
          .read(polarLoopServiceProvider)
          .exportOfflineRecord(path);
      final nextExports = Map<String, LoopExportedRecord>.from(
        state.exportsByPath,
      )..[path] = record;
      state = state.copyWith(exportsByPath: nextExports, clearLastError: true);
      await listOfflineRecordings();
      return record;
    });
  }

  Future<void> deleteOfflineRecord(String path) async {
    await _run(() async {
      await ref.read(polarLoopServiceProvider).deleteOfflineRecord(path);
      final nextDownloads = Map<String, LoopDownloadedRecord>.from(
        state.downloadsByPath,
      )..remove(path);
      final nextExports = Map<String, LoopExportedRecord>.from(
        state.exportsByPath,
      )..remove(path);
      final nextProgress = Map<String, LoopDownloadProgress>.from(
        state.downloadProgressByPath,
      )..remove(path);
      state = state.copyWith(
        downloadsByPath: nextDownloads,
        exportsByPath: nextExports,
        downloadProgressByPath: nextProgress,
        clearLastError: true,
      );
      await listOfflineRecordings();
    });
  }

  Future<int?> deleteAllOfflineRecords() async {
    return _runWithValue(() async {
      final deletedCount = await ref
          .read(polarLoopServiceProvider)
          .deleteAllOfflineRecords();
      state = state.copyWith(
        recordings: const [],
        downloadsByPath: const {},
        downloadProgressByPath: const {},
        clearLastError: true,
      );
      await listOfflineRecordings();
      return deletedCount;
    });
  }

  Future<void> clearDownloadedRecords() async {
    await _run(() async {
      await ref.read(polarLoopServiceProvider).clearDownloadedRecords();
      state = state.copyWith(
        downloadsByPath: const {},
        downloadProgressByPath: const {},
        clearLastError: true,
      );
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      state = state.copyWith(lastError: error.toString());
    }
  }

  Future<T?> _runWithValue<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error) {
      state = state.copyWith(lastError: error.toString());
      return null;
    }
  }
}

final polarLoopServiceProvider = Provider<PolarLoopService>((ref) {
  return PolarLoopService(deviceId: AppEnv.polarLoopDeviceId);
});

final loopNotifierProvider = NotifierProvider<LoopNotifier, LoopState>(
  LoopNotifier.new,
);
