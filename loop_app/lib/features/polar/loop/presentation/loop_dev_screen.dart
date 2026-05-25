import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../config/app_env.dart';
import '../../common/models/polar_connection_state.dart';
import '../logic/loop_provider.dart';
import '../models/loop_models.dart';

class LoopDevScreen extends ConsumerStatefulWidget {
  const LoopDevScreen({super.key});

  @override
  ConsumerState<LoopDevScreen> createState() => _LoopDevScreenState();
}

class _LoopDevScreenState extends ConsumerState<LoopDevScreen> {
  LoopOfflineDataType? _selectedDataType;
  final Map<LoopOfflineDataType, Map<LoopSensorSettingType, int>>
  _selectedSettingsByType = {};

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(loopNotifierProvider);
    final notifier = ref.read(loopNotifierProvider.notifier);
    final selectedType = _selectedDataType;
    final selectedSettings = selectedType == null
        ? null
        : _effectiveSelectedSettings(state, selectedType);
    final effectiveSettings = selectedType == null
        ? null
        : _effectiveSettings(state, selectedType);
    final canConnect =
        state.isConfigured &&
        (state.connectionState == PolarConnectionState.disconnected ||
            state.connectionState == PolarConnectionState.error);
    final canDisconnect =
        state.connectionState == PolarConnectionState.connected ||
        state.connectionState == PolarConnectionState.connecting ||
        state.connectionState == PolarConnectionState.scanning;
    final isConnected = state.connectionState == PolarConnectionState.connected;

    return Scaffold(
      appBar: AppBar(title: const Text('Loop Dev')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionCard(
                title: 'Connection',
                children: [
                  _InfoRow(
                    label: 'Device ID',
                    value: AppEnv.polarLoopDeviceId.isEmpty
                        ? 'Not configured'
                        : AppEnv.polarLoopDeviceId,
                  ),
                  _InfoRow(
                    label: 'Connection',
                    value: state.connectionState.name,
                  ),
                  _InfoRow(
                    label: 'Last error',
                    value: state.lastError ?? 'None',
                    valueStyle: state.lastError == null
                        ? null
                        : TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                  ),
                  _InfoRow(
                    label: 'Device time',
                    value: state.deviceTime == null
                        ? 'Not loaded'
                        : '${state.deviceTime!.localTime} (${state.deviceTime!.zoneId})',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        key: const ValueKey('loop-connect-button'),
                        onPressed: canConnect ? notifier.connect : null,
                        child: const Text('Connect'),
                      ),
                      OutlinedButton(
                        key: const ValueKey('loop-disconnect-button'),
                        onPressed: canDisconnect ? notifier.disconnect : null,
                        child: const Text('Disconnect'),
                      ),
                      OutlinedButton(
                        key: const ValueKey('loop-read-time-button'),
                        onPressed: isConnected ? notifier.getDeviceTime : null,
                        child: const Text('Read Time'),
                      ),
                      OutlinedButton(
                        key: const ValueKey('loop-set-time-button'),
                        onPressed: isConnected
                            ? () => notifier.setDeviceTime()
                            : null,
                        child: const Text('Set Time to Now'),
                      ),
                    ],
                  ),
                ],
              ),
              _SectionCard(
                title: 'Capabilities & Settings',
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        key: const ValueKey('loop-fetch-types-button'),
                        onPressed: isConnected
                            ? () => _fetchAvailableTypes(notifier)
                            : null,
                        child: const Text('Fetch Offline Data Types'),
                      ),
                      OutlinedButton(
                        key: const ValueKey('loop-refresh-status-button'),
                        onPressed: isConnected
                            ? notifier.refreshOfflineRecordingStatus
                            : null,
                        child: const Text('Refresh Active Status'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (state.availableOfflineDataTypes.isEmpty)
                    const Text('No offline data types loaded yet.')
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final type
                            in state.availableOfflineDataTypes.toList()..sort(
                              (left, right) =>
                                  left.wireName.compareTo(right.wireName),
                            ))
                          ChoiceChip(
                            key: ValueKey('loop-type-${type.wireName}'),
                            label: Text(type.wireName),
                            selected: selectedType == type,
                            onSelected: (_) {
                              setState(() {
                                _selectedDataType = type;
                              });
                            },
                          ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  if (selectedType != null) ...[
                    _InfoRow(
                      label: 'Selected type',
                      value: selectedType.wireName,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          key: const ValueKey(
                            'loop-fetch-normal-settings-button',
                          ),
                          onPressed: isConnected
                              ? () => _fetchSettings(
                                  notifier: notifier,
                                  dataType: selectedType,
                                  fullSettings: false,
                                )
                              : null,
                          child: const Text('Fetch Normal Settings'),
                        ),
                        OutlinedButton(
                          key: const ValueKey(
                            'loop-fetch-full-settings-button',
                          ),
                          onPressed: isConnected
                              ? () => _fetchSettings(
                                  notifier: notifier,
                                  dataType: selectedType,
                                  fullSettings: true,
                                )
                              : null,
                          child: const Text('Fetch Full SDK Settings'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SettingsPanel(
                      title: 'Normal Settings',
                      settings: state.normalSettingsByType[selectedType],
                    ),
                    const SizedBox(height: 12),
                    _SettingsPanel(
                      title: 'Full SDK Settings',
                      settings: state.fullSettingsByType[selectedType],
                    ),
                    const SizedBox(height: 12),
                    _SettingSelectors(
                      settings: effectiveSettings,
                      selected: selectedSettings,
                      onChanged: (settingType, value) {
                        setState(() {
                          final next = Map<LoopSensorSettingType, int>.from(
                            _selectedSettingsByType[selectedType] ??
                                _defaultSelectionFor(state, selectedType) ??
                                const {},
                          );
                          next[settingType] = value;
                          _selectedSettingsByType[selectedType] = next;
                        });
                      },
                    ),
                  ],
                ],
              ),
              _SectionCard(
                title: 'Recording Controls',
                children: [
                  _ChipList(
                    label: 'Active recording types',
                    values:
                        state.activeOfflineRecordingTypes
                            .map((type) => type.wireName)
                            .toList()
                          ..sort(),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        key: const ValueKey('loop-start-recording-button'),
                        onPressed: isConnected && selectedType != null
                            ? () => notifier.startOfflineRecording(
                                selectedType,
                                selectedSettings:
                                    selectedSettings == null ||
                                        selectedSettings.isEmpty
                                    ? null
                                    : selectedSettings,
                              )
                            : null,
                        child: const Text('Start Recording'),
                      ),
                      OutlinedButton(
                        key: const ValueKey('loop-stop-recording-button'),
                        onPressed: isConnected && selectedType != null
                            ? () => notifier.stopOfflineRecording(selectedType)
                            : null,
                        child: const Text('Stop Recording'),
                      ),
                    ],
                  ),
                ],
              ),
              _SectionCard(
                title: 'Offline Recordings',
                trailing: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      key: const ValueKey('loop-list-recordings-button'),
                      onPressed: isConnected
                          ? notifier.listOfflineRecordings
                          : null,
                      child: const Text('List Recordings'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('loop-clear-loop-recordings-button'),
                      onPressed: isConnected && state.recordings.isNotEmpty
                          ? () => _confirmDeleteAllFromLoop(
                              notifier: notifier,
                              recordingCount: state.recordings.length,
                            )
                          : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      child: const Text('Clear Loop'),
                    ),
                  ],
                ),
                children: [
                  if (state.recordings.isEmpty)
                    const Text('No recordings loaded yet.')
                  else
                    for (final entry in state.recordings) ...[
                      _RecordingCard(
                        entry: entry,
                        onDownload: isConnected
                            ? () => notifier.downloadOfflineRecord(entry.path)
                            : null,
                        onExport: isConnected
                            ? () => _exportOfflineRecord(
                                notifier: notifier,
                                path: entry.path,
                              )
                            : null,
                        onExportAndShare: isConnected
                            ? () => _exportAndShareOfflineRecord(
                                notifier: notifier,
                                path: entry.path,
                              )
                            : null,
                        onDelete: isConnected && entry.exportConfirmed
                            ? () => _confirmDeleteFromLoop(
                                notifier: notifier,
                                entry: entry,
                              )
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
              _SectionCard(
                title: 'Transfer & Export State',
                trailing: OutlinedButton(
                  key: const ValueKey('loop-clear-downloaded-records-button'),
                  onPressed:
                      state.downloadsByPath.isNotEmpty ||
                          state.downloadProgressByPath.isNotEmpty
                      ? () => _confirmClearDownloadedRecords(notifier)
                      : null,
                  child: const Text('Clear Downloads'),
                ),
                children: [
                  _ProgressPanel(progressByPath: state.downloadProgressByPath),
                  const SizedBox(height: 12),
                  _DownloadedRecordPanel(
                    downloadsByPath: state.downloadsByPath,
                  ),
                  const SizedBox(height: 12),
                  _ExportedRecordPanel(
                    exportsByPath: state.exportsByPath,
                    canDeleteFromLoop: isConnected,
                    onShare: _shareExportedRecord,
                    onDeleteFromLoop: (record) => _confirmDeleteFromLoop(
                      notifier: notifier,
                      entry: record.entry,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _fetchAvailableTypes(LoopNotifier notifier) async {
    final types = await notifier.fetchAvailableOfflineDataTypes();
    if (!mounted || types == null || types.isEmpty) return;
    final sortedTypes = types.toList()
      ..sort((left, right) => left.wireName.compareTo(right.wireName));
    setState(() {
      if (_selectedDataType == null || !types.contains(_selectedDataType)) {
        _selectedDataType = sortedTypes.first;
      }
    });
  }

  Future<void> _fetchSettings({
    required LoopNotifier notifier,
    required LoopOfflineDataType dataType,
    required bool fullSettings,
  }) async {
    final settings = fullSettings
        ? await notifier.requestFullOfflineRecordingSettings(dataType)
        : await notifier.requestOfflineRecordingSettings(dataType);
    if (!mounted || settings == null) return;
    setState(() {
      _selectedDataType = dataType;
      _selectedSettingsByType[dataType] = _selectionFromSettings(
        dataType,
        settings,
      );
    });
  }

  LoopSensorSettings? _effectiveSettings(
    LoopState state,
    LoopOfflineDataType dataType,
  ) {
    return state.fullSettingsByType[dataType] ??
        state.normalSettingsByType[dataType];
  }

  Map<LoopSensorSettingType, int>? _defaultSelectionFor(
    LoopState state,
    LoopOfflineDataType dataType,
  ) {
    return _effectiveSettings(state, dataType)?.maxSelection;
  }

  Future<void> _exportOfflineRecord({
    required LoopNotifier notifier,
    required String path,
  }) async {
    final record = await notifier.exportOfflineRecord(path);
    if (!mounted || record == null) return;
    _showMessage(
      'Exported ${record.entry.dataType.wireName} to Downloads/Polar Loop.',
    );
  }

  Future<void> _exportAndShareOfflineRecord({
    required LoopNotifier notifier,
    required String path,
  }) async {
    final record = await notifier.exportOfflineRecord(path);
    if (!mounted || record == null) return;
    await _shareExportedRecord(record);
  }

  Future<void> _shareExportedRecord(LoopExportedRecord record) async {
    final rawFile = File(record.shareRawFilePath);
    final summaryFile = File(record.shareSummaryFilePath);
    final files = <XFile>[];

    if (await rawFile.exists()) {
      files.add(XFile(rawFile.path, name: rawFile.uri.pathSegments.last));
    }
    if (await summaryFile.exists()) {
      files.add(
        XFile(summaryFile.path, name: summaryFile.uri.pathSegments.last),
      );
    }

    if (!mounted) return;
    if (files.isEmpty) {
      _showMessage(
        'No exported files found for ${record.entry.path}. Re-export and try again.',
      );
      return;
    }

    await SharePlus.instance.share(
      ShareParams(
        title: 'Share Polar Loop export',
        text: 'Polar Loop export: ${record.entry.path}',
        files: files,
      ),
    );
  }

  Future<void> _confirmDeleteFromLoop({
    required LoopNotifier notifier,
    required LoopOfflineRecordingEntry entry,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete from Loop'),
          content: Text(
            'Delete ${entry.dataType.wireName} recording from the Loop device?\n\n'
            'Path: ${entry.path}\n\n'
            'Exported files already saved on the phone will remain available.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await notifier.deleteOfflineRecord(entry.path);
    if (!mounted) return;
    _showMessage('Deleted ${entry.dataType.wireName} recording from the Loop.');
  }

  Future<void> _confirmDeleteAllFromLoop({
    required LoopNotifier notifier,
    required int recordingCount,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear Loop Recordings'),
          content: Text(
            'Delete all $recordingCount recording(s) from the Loop device?\n\n'
            'This does not remove exported files already saved on the phone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete All'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    final deletedCount = await notifier.deleteAllOfflineRecords();
    if (!mounted || deletedCount == null) return;
    _showMessage('Deleted $deletedCount recording(s) from the Loop.');
  }

  Future<void> _confirmClearDownloadedRecords(LoopNotifier notifier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear Downloaded Records'),
          content: const Text(
            'Clear downloaded records and transfer progress from this app?\n\n'
            'Exported files already saved on the phone will remain available.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await notifier.clearDownloadedRecords();
    if (!mounted) return;
    _showMessage('Cleared downloaded records from the app.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Map<LoopSensorSettingType, int>? _effectiveSelectedSettings(
    LoopState state,
    LoopOfflineDataType dataType,
  ) {
    final availableSettings = _effectiveSettings(state, dataType);
    if (availableSettings == null || availableSettings.values.isEmpty) {
      return null;
    }
    final defaults = Map<LoopSensorSettingType, int>.from(
      availableSettings.maxSelection,
    );
    final current = _selectedSettingsByType[dataType] ?? const {};
    for (final entry in current.entries) {
      if (availableSettings.values[entry.key]?.contains(entry.value) ?? false) {
        defaults[entry.key] = entry.value;
      }
    }
    return defaults;
  }

  Map<LoopSensorSettingType, int> _selectionFromSettings(
    LoopOfflineDataType dataType,
    LoopSensorSettings settings,
  ) {
    final current = _selectedSettingsByType[dataType] ?? const {};
    return {
      for (final entry in settings.values.entries)
        entry.key: entry.value.contains(current[entry.key])
            ? current[entry.key]!
            : entry.value.last,
    };
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    this.trailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (trailing != null) ...[trailing!],
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? valueStyle;

  const _InfoRow({required this.label, required this.value, this.valueStyle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: valueStyle ?? Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipList extends StatelessWidget {
  final String label;
  final List<String> values;

  const _ChipList({required this.label, required this.values});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (values.isEmpty)
          const Text('None')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final value in values) Chip(label: Text(value))],
          ),
      ],
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  final String title;
  final LoopSensorSettings? settings;

  const _SettingsPanel({required this.title, required this.settings});

  @override
  Widget build(BuildContext context) {
    final settingsValue = settings;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (settingsValue == null)
              const Text('Not loaded')
            else if (settingsValue.values.isEmpty)
              const Text('No selectable settings')
            else
              for (final entry in settingsValue.values.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${entry.key.wireName}: ${entry.value.join(', ')}',
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _SettingSelectors extends StatelessWidget {
  final LoopSensorSettings? settings;
  final Map<LoopSensorSettingType, int>? selected;
  final void Function(LoopSensorSettingType settingType, int value) onChanged;

  const _SettingSelectors({
    required this.settings,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final settingsValue = settings;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Selected Settings',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (settingsValue == null)
              const Text(
                'Fetch settings for the selected data type to edit values.',
              )
            else if (settingsValue.values.isEmpty)
              const Text(
                'This data type does not expose selectable settings for start.',
              )
            else
              for (final entry in settingsValue.values.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('loop-setting-${entry.key.wireName}'),
                    initialValue: selected?[entry.key] ?? entry.value.last,
                    decoration: InputDecoration(
                      labelText: entry.key.wireName,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final value in entry.value)
                        DropdownMenuItem<int>(
                          value: value,
                          child: Text(value.toString()),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      onChanged(entry.key, value);
                    },
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

class _RecordingCard extends StatelessWidget {
  final LoopOfflineRecordingEntry entry;
  final VoidCallback? onDownload;
  final VoidCallback? onExport;
  final VoidCallback? onExportAndShare;
  final VoidCallback? onDelete;

  const _RecordingCard({
    required this.entry,
    required this.onDownload,
    required this.onExport,
    required this.onExportAndShare,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoRow(label: 'Path', value: entry.path),
            _InfoRow(label: 'Type', value: entry.dataType.wireName),
            _InfoRow(label: 'Size', value: '${entry.sizeBytes} bytes'),
            _InfoRow(label: 'Started', value: entry.startedAt.toString()),
            _InfoRow(
              label: 'Exported',
              value: entry.exportConfirmed ? 'Yes' : 'No',
            ),
            if (!entry.exportConfirmed) ...[
              const SizedBox(height: 4),
              const Text('Export once before device-side deletion is enabled.'),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: ValueKey('loop-recording-${entry.path}-download'),
                  onPressed: onDownload,
                  child: const Text('Download'),
                ),
                OutlinedButton(
                  key: ValueKey('loop-recording-${entry.path}-export'),
                  onPressed: onExport,
                  child: const Text('Export Files'),
                ),
                FilledButton.tonal(
                  key: ValueKey('loop-recording-${entry.path}-export-share'),
                  onPressed: onExportAndShare,
                  child: const Text('Export & Share'),
                ),
                OutlinedButton(
                  key: ValueKey('loop-recording-${entry.path}-delete'),
                  onPressed: onDelete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  child: const Text('Delete from Loop'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  final Map<String, LoopDownloadProgress> progressByPath;

  const _ProgressPanel({required this.progressByPath});

  @override
  Widget build(BuildContext context) {
    final progressItems = progressByPath.values.toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Download Progress',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (progressItems.isEmpty)
          const Text('No active downloads')
        else
          for (final progress in progressItems)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectableText(progress.path),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: progress.totalBytes == 0
                        ? null
                        : progress.bytesDownloaded / progress.totalBytes,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${progress.progressPercent}% '
                    '(${progress.bytesDownloaded}/${progress.totalBytes} bytes)',
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _DownloadedRecordPanel extends StatelessWidget {
  final Map<String, LoopDownloadedRecord> downloadsByPath;

  const _DownloadedRecordPanel({required this.downloadsByPath});

  @override
  Widget build(BuildContext context) {
    final records = downloadsByPath.values.toList()
      ..sort((left, right) => left.entry.path.compareTo(right.entry.path));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Downloaded Records',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (records.isEmpty)
          const Text('No downloaded records')
        else
          for (final record in records) ...[
            _SummaryCard(
              title: record.entry.path,
              headerRows: [
                _InfoRow(
                  label: 'Downloaded',
                  value: record.downloadedAt.toString(),
                ),
                if (record.selectedSettings != null)
                  _InfoRow(
                    label: 'Selected settings',
                    value: record.selectedSettings!.entries
                        .map(
                          (entry) =>
                              '${entry.key.wireName}=${entry.value.join('/')}',
                        )
                        .join(', '),
                  ),
              ],
              summary: record.summary,
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _ExportedRecordPanel extends StatelessWidget {
  final Map<String, LoopExportedRecord> exportsByPath;
  final bool canDeleteFromLoop;
  final Future<void> Function(LoopExportedRecord record) onShare;
  final Future<void> Function(LoopExportedRecord record) onDeleteFromLoop;

  const _ExportedRecordPanel({
    required this.exportsByPath,
    required this.canDeleteFromLoop,
    required this.onShare,
    required this.onDeleteFromLoop,
  });

  @override
  Widget build(BuildContext context) {
    final records = exportsByPath.values.toList()
      ..sort((left, right) => left.entry.path.compareTo(right.entry.path));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Exports',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (records.isEmpty)
          const Text('No exports')
        else
          for (final record in records) ...[
            _SummaryCard(
              title: record.entry.path,
              headerRows: [
                _InfoRow(
                  label: 'Exported',
                  value: record.exportedAt.toString(),
                ),
                _InfoRow(label: 'Data file', value: record.rawFilePath),
                _InfoRow(label: 'Summary file', value: record.summaryFilePath),
              ],
              actions: [
                FilledButton(
                  onPressed: () => onShare(record),
                  child: const Text('Share Files'),
                ),
                OutlinedButton(
                  onPressed: canDeleteFromLoop
                      ? () => onDeleteFromLoop(record)
                      : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                  child: const Text('Delete from Loop'),
                ),
              ],
              summary: record.summary,
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final List<Widget> headerRows;
  final List<Widget> actions;
  final LoopOfflineRecordSummary summary;

  const _SummaryCard({
    required this.title,
    required this.headerRows,
    this.actions = const [],
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final metricEntries = summary.metrics.entries.toList()
      ..sort((left, right) => left.key.compareTo(right.key));
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...headerRows,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
            _InfoRow(label: 'Samples', value: summary.sampleCount.toString()),
            _InfoRow(
              label: 'First timestamp',
              value: summary.firstSampleTimestampNs?.toString() ?? 'None',
            ),
            _InfoRow(
              label: 'Last timestamp',
              value: summary.lastSampleTimestampNs?.toString() ?? 'None',
            ),
            if (metricEntries.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Metrics',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              for (final metric in metricEntries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SelectableText('${metric.key}: ${metric.value}'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
