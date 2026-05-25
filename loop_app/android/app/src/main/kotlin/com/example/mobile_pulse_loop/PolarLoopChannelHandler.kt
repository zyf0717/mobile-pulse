package com.example.mobile_pulse_loop

import android.content.ContentValues
import android.os.Handler
import android.os.Looper
import android.os.Environment
import android.provider.MediaStore
import com.polar.sdk.api.PolarBleApi
import com.polar.sdk.api.model.PolarAccelerometerData
import com.polar.sdk.api.model.PolarHrData
import com.polar.sdk.api.model.PolarOfflineRecordingData
import com.polar.sdk.api.model.PolarOfflineRecordingEntry
import com.polar.sdk.api.model.PolarOfflineRecordingResult
import com.polar.sdk.api.model.PolarPpgData
import com.polar.sdk.api.model.PolarPpiData
import com.polar.sdk.api.model.PolarSensorSetting
import com.polar.sdk.api.model.PolarTemperatureData
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZonedDateTime

class PolarLoopChannelHandler(
    sharedPolarBleApi: SharedPolarBleApi,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val METHOD_CHANNEL = "com.example.mobile_pulse_loop/polar_loop/methods"
        private const val EVENT_CHANNEL = "com.example.mobile_pulse_loop/polar_loop/events"
        private const val CONNECT_TIMEOUT_MS = 15_000L
    }

    private data class CachedDownload(
        val entry: PolarOfflineRecordingEntry,
        val data: PolarOfflineRecordingData,
        val downloadedAt: Instant,
        val summary: Map<String, Any?>,
    )

    private val sharedApi = sharedPolarBleApi
    private val api: PolarBleApi = sharedApi.api
    private val appContext = sharedApi.appContext
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val connectTimeoutRunnable = Runnable {
        if (connectedIdentifier != null || deviceId.isBlank()) return@Runnable
        emitConnection("error")
        emitError(
            scope = "connection",
            message = "Timed out waiting for Polar Loop/360 $deviceId. Verify the device is paired, nearby, and powered on.",
        )
    }

    private var eventSink: EventChannel.EventSink? = null
    private var deviceId: String = ""
    private var connectedIdentifier: String? = null
    private val readyFeatures = mutableSetOf<PolarBleApi.PolarBleSdkFeature>()
    private val offlineEntryCache = mutableMapOf<String, PolarOfflineRecordingEntry>()
    private val downloadCache = mutableMapOf<String, CachedDownload>()
    private val apiListener = object : SharedPolarBleApi.Listener {
        override fun deviceConnecting(polarDeviceInfo: com.polar.sdk.api.model.PolarDeviceInfo) {
            if (!matches(polarDeviceInfo.deviceId)) return
            cancelConnectTimeout()
            emitConnection("connecting")
        }

        override fun deviceConnected(polarDeviceInfo: com.polar.sdk.api.model.PolarDeviceInfo) {
            if (!matches(polarDeviceInfo.deviceId)) return
            cancelConnectTimeout()
            connectedIdentifier = polarDeviceInfo.deviceId
            emitConnection("connected")
        }

        override fun deviceDisconnected(polarDeviceInfo: com.polar.sdk.api.model.PolarDeviceInfo) {
            if (!matches(polarDeviceInfo.deviceId)) return
            cancelConnectTimeout()
            connectedIdentifier = null
            readyFeatures.clear()
            offlineEntryCache.clear()
            downloadCache.clear()
            emitConnection("disconnected")
        }

        override fun bleSdkFeatureReady(
            identifier: String,
            feature: PolarBleApi.PolarBleSdkFeature,
        ) {
            if (!matches(identifier)) return
            connectedIdentifier = identifier
            readyFeatures.add(feature)
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        sharedApi.addListener(apiListener)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "connect" -> {
                val nextDeviceId = call.argument<String>("deviceId").orEmpty()
                if (nextDeviceId.isBlank()) {
                    result.error("missing_device_id", "POLAR_LOOP_DEVICE_ID is not set", null)
                    return
                }
                deviceId = nextDeviceId
                connectedIdentifier = null
                readyFeatures.clear()
                offlineEntryCache.clear()
                downloadCache.clear()
                emitConnection("scanning")
                api.connectToDevice(deviceId)
                scheduleConnectTimeout()
                result.success(null)
            }

            "disconnect" -> {
                cancelConnectTimeout()
                connectedIdentifier?.let(api::disconnectFromDevice)
                connectedIdentifier = null
                readyFeatures.clear()
                offlineEntryCache.clear()
                downloadCache.clear()
                result.success(null)
            }

            "getDeviceTime" -> launchMethod(result) {
                val identifier = requireConnectedIdentifier()
                requireFeatureReady(
                    identifier,
                    PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_DEVICE_TIME_SETUP,
                )
                timePayload(api.getLocalTimeWithZone(identifier))
            }

            "setDeviceTime" -> launchMethod(result) {
                val identifier = requireConnectedIdentifier()
                requireFeatureReady(
                    identifier,
                    PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_DEVICE_TIME_SETUP,
                )
                val localTime = call.argument<String>("localTime")
                    ?: throw IllegalArgumentException("localTime is required")
                api.setLocalTime(identifier, parseLocalDateTime(localTime))
                timePayload(api.getLocalTimeWithZone(identifier))
            }

            "getAvailableOfflineDataTypes" -> launchMethod(result) {
                val identifier = requireConnectedIdentifier()
                requireFeatureReady(
                    identifier,
                    PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_OFFLINE_RECORDING,
                )
                api.getAvailableOfflineRecordingDataTypes(identifier)
                    .map { it.name }
                    .sorted()
            }

            "requestOfflineRecordingSettings" -> launchMethod(result) {
                val identifier = requireConnectedIdentifier()
                requireFeatureReady(
                    identifier,
                    PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_OFFLINE_RECORDING,
                )
                val dataType = dataTypeFromCall(call)
                val fullSettings = call.argument<Boolean>("fullSettings") ?: false
                val settings = if (fullSettings) {
                    api.requestFullOfflineRecordingSettings(identifier, dataType)
                } else {
                    api.requestOfflineRecordingSettings(identifier, dataType)
                }
                sensorSettingsPayload(dataType, settings, fullSettings)
            }

            "getOfflineRecordingStatus" -> launchMethod(result) {
                val identifier = requireConnectedIdentifier()
                requireFeatureReady(
                    identifier,
                    PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_OFFLINE_RECORDING,
                )
                api.getOfflineRecordingStatus(identifier)
                    .map { it.name }
                    .sorted()
            }

            "startOfflineRecording" -> launchMethod(result) {
                val identifier = requireConnectedIdentifier()
                requireFeatureReady(
                    identifier,
                    PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_OFFLINE_RECORDING,
                )
                val dataType = dataTypeFromCall(call)
                val settings = call.argument<Map<*, *>>("settings")
                    ?.let(::selectedSensorSettingFromMap)
                api.startOfflineRecording(identifier, dataType, settings, null)
                null
            }

            "stopOfflineRecording" -> launchMethod(result) {
                val identifier = requireConnectedIdentifier()
                requireFeatureReady(
                    identifier,
                    PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_OFFLINE_RECORDING,
                )
                api.stopOfflineRecording(identifier, dataTypeFromCall(call))
                null
            }

            "listOfflineRecordings" -> launchMethod(result) {
                val identifier = requireConnectedIdentifier()
                requireFeatureReady(
                    identifier,
                    PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_OFFLINE_RECORDING,
                )
                val entries = api.listOfflineRecordings(identifier).toList()
                    .sortedByDescending { it.date }
                offlineEntryCache.clear()
                entries.forEach { offlineEntryCache[it.path] = it }
                entries.map(::recordingEntryPayload)
            }

            "downloadOfflineRecord" -> launchMethod(result) {
                val identifier = requireConnectedIdentifier()
                requireFeatureReady(
                    identifier,
                    PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_OFFLINE_RECORDING,
                )
                val path = call.argument<String>("path")
                    ?: throw IllegalArgumentException("path is required")
                val entry = resolveEntry(identifier, path)
                val cachedDownload = fetchOfflineRecord(identifier, entry, emitProgress = true)
                downloadedRecordPayload(cachedDownload)
            }

            "exportOfflineRecord" -> launchMethod(result) {
                val identifier = requireConnectedIdentifier()
                requireFeatureReady(
                    identifier,
                    PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_OFFLINE_RECORDING,
                )
                val path = call.argument<String>("path")
                    ?: throw IllegalArgumentException("path is required")
                val entry = resolveEntry(identifier, path)
                val cachedDownload = fetchOfflineRecord(identifier, entry, emitProgress = false)
                val exportPayload = exportOfflineRecord(identifier, entry, cachedDownload)
                exportPayload
            }

            "deleteOfflineRecord" -> launchMethod(result) {
                val identifier = requireConnectedIdentifier()
                requireFeatureReady(
                    identifier,
                    PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_OFFLINE_RECORDING,
                )
                val path = call.argument<String>("path")
                    ?: throw IllegalArgumentException("path is required")
                val entry = resolveEntry(identifier, path)
                if (!isExportConfirmed(entry)) {
                    throw IllegalStateException(
                        "Offline recording $path must be exported successfully before deletion.",
                    )
                }
                api.removeOfflineRecord(identifier, entry)
                offlineEntryCache.remove(path)
                downloadCache.remove(path)
                null
            }

            "deleteAllOfflineRecords" -> launchMethod(result) {
                val identifier = requireConnectedIdentifier()
                requireFeatureReady(
                    identifier,
                    PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_OFFLINE_RECORDING,
                )
                val entries = api.listOfflineRecordings(identifier).toList()
                entries.forEach { entry ->
                    api.removeOfflineRecord(identifier, entry)
                    offlineEntryCache.remove(entry.path)
                    downloadCache.remove(entry.path)
                }
                entries.size
            }

            "clearDownloadedRecords" -> launchMethod(result) {
                downloadCache.clear()
                null
            }

            else -> result.notImplemented()
        }
    }

    fun dispose() {
        cancelConnectTimeout()
        scope.cancel()
        sharedApi.removeListener(apiListener)
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    private fun launchMethod(
        result: MethodChannel.Result,
        block: suspend () -> Any?,
    ) {
        scope.launch {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (error: Throwable) {
                val message = friendlyErrorMessage(error)
                emitError(
                    scope = "method",
                    message = message,
                    code = error.javaClass.simpleName,
                )
                mainHandler.post {
                    result.error(
                        error.javaClass.simpleName,
                        message,
                        null,
                    )
                }
            }
        }
    }

    private suspend fun fetchOfflineRecord(
        identifier: String,
        entry: PolarOfflineRecordingEntry,
        emitProgress: Boolean,
    ): CachedDownload {
        downloadCache[entry.path]?.let { return it }
        var completed: PolarOfflineRecordingData? = null
        api.getOfflineRecordWithProgress(identifier, entry, null).collect { event ->
            when (event) {
                is PolarOfflineRecordingResult.Progress -> {
                    if (emitProgress) {
                        emit(
                            mapOf(
                                "type" to "download_progress",
                                "path" to entry.path,
                                "bytes_downloaded" to event.bytesDownloaded,
                                "total_bytes" to event.totalBytes,
                                "progress_percent" to event.progressPercent,
                            ),
                        )
                    }
                }

                is PolarOfflineRecordingResult.Complete -> {
                    completed = event.data
                }
            }
        }
        val data = completed
            ?: throw IllegalStateException("Download completed without recording data")
        val cached = CachedDownload(
            entry = entry,
            data = data,
            downloadedAt = Instant.now(),
            summary = buildSummary(data),
        )
        downloadCache[entry.path] = cached
        return cached
    }

    private suspend fun exportOfflineRecord(
        identifier: String,
        entry: PolarOfflineRecordingEntry,
        cachedDownload: CachedDownload,
    ): Map<String, Any?> {
        val exportDir = privateExportDirectoryForEntry(entry)
        if (!exportDir.exists()) {
            exportDir.mkdirs()
        }

        val rawFile = privateRawExportFile(entry)
        val summaryFile = privateSummaryExportFile(entry)
        val exportedPayload = linkedMapOf<String, Any?>(
            "entry" to recordingEntryPayload(entry),
            "downloaded_at" to cachedDownload.downloadedAt.toString(),
            "settings" to cachedDownload.data.settings?.let(::selectedSensorSettingsPayload),
            "summary" to cachedDownload.summary,
            "data" to offlineRecordingDataPayload(cachedDownload.data),
        )
        val exportedJson = JSONObject(exportedPayload).toString(2)
        rawFile.writeText(exportedJson)

        val summaryPayload = linkedMapOf<String, Any?>(
            "entry" to recordingEntryPayload(entry),
            "exported_at" to Instant.now().toString(),
            "summary" to cachedDownload.summary,
            "settings" to cachedDownload.data.settings?.let(::selectedSensorSettingsPayload),
            "source_device_id" to identifier,
            "source_path" to entry.path,
        )
        val summaryJson = JSONObject(summaryPayload).toString(2)
        summaryFile.writeText(summaryJson)

        if (!rawFile.isFile || !summaryFile.isFile) {
            throw IllegalStateException("Export verification failed for ${entry.path}")
        }

        val publicRawFilePath = writePublicExportFile(
            entry = entry,
            fileName = rawFile.name,
            mimeType = "application/json",
            content = exportedJson,
        )
        val publicSummaryFilePath = writePublicExportFile(
            entry = entry,
            fileName = summaryFile.name,
            mimeType = "application/json",
            content = summaryJson,
        )

        return linkedMapOf(
            "entry" to recordingEntryPayload(entry),
            "exported_at" to summaryPayload["exported_at"],
            "raw_file_path" to publicRawFilePath,
            "summary_file_path" to publicSummaryFilePath,
            "share_raw_file_path" to rawFile.absolutePath,
            "share_summary_file_path" to summaryFile.absolutePath,
            "summary" to cachedDownload.summary,
        )
    }

    private fun timePayload(deviceTime: ZonedDateTime): Map<String, Any?> {
        return linkedMapOf(
            "local_time" to deviceTime.toLocalDateTime().toString(),
            "zone_id" to deviceTime.zone.id,
            "offset_seconds" to deviceTime.offset.totalSeconds,
        )
    }

    private fun sensorSettingsPayload(
        dataType: PolarBleApi.PolarDeviceDataType,
        settings: PolarSensorSetting,
        fullSettings: Boolean,
    ): Map<String, Any?> {
        return linkedMapOf(
            "data_type" to dataType.name,
            "full_settings" to fullSettings,
            "values" to availableSensorSettingsPayload(settings),
        )
    }

    private fun availableSensorSettingsPayload(
        settings: PolarSensorSetting,
    ): Map<String, List<Int>> {
        return settings.settings.entries.associate { entry ->
            entry.key.name.lowercase()
                .replace("sample_rate", "sample_rate")
                .replace("resolution", "resolution")
                .replace("range", "range")
                .replace("channels", "channels") to entry.value.sorted()
        }
    }

    private fun selectedSensorSettingsPayload(
        settings: PolarSensorSetting,
    ): Map<String, List<Int>> {
        return settings.settings.entries.associate { entry ->
            entry.key.name.lowercase()
                .replace("sample_rate", "sample_rate")
                .replace("resolution", "resolution")
                .replace("range", "range")
                .replace("channels", "channels") to entry.value.sorted()
        }
    }

    private fun recordingEntryPayload(entry: PolarOfflineRecordingEntry): Map<String, Any?> {
        return linkedMapOf(
            "path" to entry.path,
            "size_bytes" to entry.size,
            "started_at" to entry.date.toString(),
            "data_type" to entry.type.name,
            "export_confirmed" to isExportConfirmed(entry),
        )
    }

    private fun downloadedRecordPayload(cachedDownload: CachedDownload): Map<String, Any?> {
        return linkedMapOf(
            "entry" to recordingEntryPayload(cachedDownload.entry),
            "downloaded_at" to cachedDownload.downloadedAt.toString(),
            "settings" to cachedDownload.data.settings?.let(::selectedSensorSettingsPayload),
            "summary" to cachedDownload.summary,
        )
    }

    private fun buildSummary(data: PolarOfflineRecordingData): Map<String, Any?> {
        return when (data) {
            is PolarOfflineRecordingData.AccOfflineRecording -> {
                xyzSummary(
                    samples = data.data.samples,
                    timestamp = { it.timeStamp },
                    axes = { Triple(it.x, it.y, it.z) },
                )
            }

            is PolarOfflineRecordingData.GyroOfflineRecording -> {
                xyzSummary(
                    samples = data.data.samples,
                    timestamp = { it.timeStamp },
                    axes = { Triple(it.x, it.y, it.z) },
                )
            }

            is PolarOfflineRecordingData.MagOfflineRecording -> {
                xyzSummary(
                    samples = data.data.samples,
                    timestamp = { it.timeStamp },
                    axes = { Triple(it.x, it.y, it.z) },
                )
            }

            is PolarOfflineRecordingData.PpgOfflineRecording -> {
                val samples = data.data.samples
                val flattenedChannels = samples.flatMap(PolarPpgData.PolarPpgSample::channelSamples)
                linkedMapOf(
                    "sample_count" to samples.size,
                    "first_sample_timestamp_ns" to samples.firstOrNull()?.timeStamp,
                    "last_sample_timestamp_ns" to samples.lastOrNull()?.timeStamp,
                    "metrics" to linkedMapOf(
                        "ppg_type" to data.data.type.name,
                        "channel_count" to (samples.firstOrNull()?.channelSamples?.size ?: 0),
                        "status_bits_per_sample" to (samples.firstOrNull()?.statusBits?.size ?: 0),
                        "min_channel_value" to flattenedChannels.minOrNull(),
                        "max_channel_value" to flattenedChannels.maxOrNull(),
                    ),
                )
            }

            is PolarOfflineRecordingData.PpiOfflineRecording -> {
                val samples = data.data.samples
                linkedMapOf(
                    "sample_count" to samples.size,
                    "first_sample_timestamp_ns" to samples.firstOrNull()?.timeStamp?.toLong(),
                    "last_sample_timestamp_ns" to samples.lastOrNull()?.timeStamp?.toLong(),
                    "metrics" to linkedMapOf(
                        "min_ppi_ms" to samples.minOfOrNull(PolarPpiData.PolarPpiSample::ppi),
                        "max_ppi_ms" to samples.maxOfOrNull(PolarPpiData.PolarPpiSample::ppi),
                        "avg_ppi_ms" to samples.map(PolarPpiData.PolarPpiSample::ppi).averageIntOrNull(),
                        "min_hr" to samples.minOfOrNull(PolarPpiData.PolarPpiSample::hr),
                        "max_hr" to samples.maxOfOrNull(PolarPpiData.PolarPpiSample::hr),
                        "avg_hr" to samples.map(PolarPpiData.PolarPpiSample::hr).averageIntOrNull(),
                    ),
                )
            }

            is PolarOfflineRecordingData.HrOfflineRecording -> {
                val samples = data.data.samples
                linkedMapOf(
                    "sample_count" to samples.size,
                    "first_sample_timestamp_ns" to null,
                    "last_sample_timestamp_ns" to null,
                    "metrics" to linkedMapOf(
                        "min_hr" to samples.minOfOrNull(PolarHrData.PolarHrSample::hr),
                        "max_hr" to samples.maxOfOrNull(PolarHrData.PolarHrSample::hr),
                        "avg_hr" to samples.map(PolarHrData.PolarHrSample::hr).averageIntOrNull(),
                        "rr_sample_count" to samples.sumOf { it.rrsMs.size },
                    ),
                )
            }

            is PolarOfflineRecordingData.TemperatureOfflineRecording -> {
                temperatureSummary(data.data.samples)
            }

            is PolarOfflineRecordingData.SkinTemperatureOfflineRecording -> {
                temperatureSummary(data.data.samples)
            }
        }
    }

    private fun <T> xyzSummary(
        samples: List<T>,
        timestamp: (T) -> Long,
        axes: (T) -> Triple<Number, Number, Number>,
    ): Map<String, Any?> {
        if (samples.isEmpty()) {
            return linkedMapOf(
                "sample_count" to 0,
                "first_sample_timestamp_ns" to null,
                "last_sample_timestamp_ns" to null,
                "metrics" to emptyMap<String, Any?>(),
            )
        }
        val xs = samples.map { axes(it).first.toDouble() }
        val ys = samples.map { axes(it).second.toDouble() }
        val zs = samples.map { axes(it).third.toDouble() }
        return linkedMapOf(
            "sample_count" to samples.size,
            "first_sample_timestamp_ns" to timestamp(samples.first()),
            "last_sample_timestamp_ns" to timestamp(samples.last()),
            "metrics" to linkedMapOf(
                "min_x" to xs.minOrNull(),
                "max_x" to xs.maxOrNull(),
                "min_y" to ys.minOrNull(),
                "max_y" to ys.maxOrNull(),
                "min_z" to zs.minOrNull(),
                "max_z" to zs.maxOrNull(),
            ),
        )
    }

    private fun temperatureSummary(
        samples: List<PolarTemperatureData.PolarTemperatureDataSample>,
    ): Map<String, Any?> {
        return linkedMapOf(
            "sample_count" to samples.size,
            "first_sample_timestamp_ns" to samples.firstOrNull()?.timeStamp,
            "last_sample_timestamp_ns" to samples.lastOrNull()?.timeStamp,
            "metrics" to linkedMapOf(
                "min_temperature_c" to samples.minOfOrNull(PolarTemperatureData.PolarTemperatureDataSample::temperature),
                "max_temperature_c" to samples.maxOfOrNull(PolarTemperatureData.PolarTemperatureDataSample::temperature),
                "avg_temperature_c" to samples.map(PolarTemperatureData.PolarTemperatureDataSample::temperature).averageFloatOrNull(),
            ),
        )
    }

    private fun dataTypeFromCall(call: MethodCall): PolarBleApi.PolarDeviceDataType {
        val dataType = call.argument<String>("dataType")
            ?: throw IllegalArgumentException("dataType is required")
        return PolarBleApi.PolarDeviceDataType.valueOf(dataType)
    }

    private fun selectedSensorSettingFromMap(raw: Map<*, *>): PolarSensorSetting {
        val settings = raw.entries.associate { entry ->
            val key = (entry.key as? String)
                ?: throw IllegalArgumentException("Sensor setting key must be a string")
            val value = (entry.value as? Number)?.toInt()
                ?: throw IllegalArgumentException("Sensor setting value must be numeric")
            settingTypeFromWireName(key) to value
        }
        return PolarSensorSetting(settings)
    }

    private fun settingTypeFromWireName(value: String): PolarSensorSetting.SettingType {
        return when (value) {
            "sample_rate" -> PolarSensorSetting.SettingType.SAMPLE_RATE
            "resolution" -> PolarSensorSetting.SettingType.RESOLUTION
            "range" -> PolarSensorSetting.SettingType.RANGE
            "channels" -> PolarSensorSetting.SettingType.CHANNELS
            else -> throw IllegalArgumentException("Unsupported setting type $value")
        }
    }

    private suspend fun resolveEntry(
        identifier: String,
        path: String,
    ): PolarOfflineRecordingEntry {
        offlineEntryCache[path]?.let { return it }
        val entries = api.listOfflineRecordings(identifier).toList()
        entries.forEach { offlineEntryCache[it.path] = it }
        return offlineEntryCache[path]
            ?: throw IllegalArgumentException("No offline recording entry found for path $path")
    }

    private fun requireConnectedIdentifier(): String {
        return connectedIdentifier
            ?: throw IllegalStateException("Polar Loop/360 is not connected")
    }

    private fun requireFeatureReady(
        identifier: String,
        feature: PolarBleApi.PolarBleSdkFeature,
    ) {
        if (feature in readyFeatures) return
        if (api.isFeatureReady(identifier, feature)) return
        throw IllegalStateException("Polar SDK feature $feature is not ready")
    }

    private fun scheduleConnectTimeout() {
        cancelConnectTimeout()
        mainHandler.postDelayed(connectTimeoutRunnable, CONNECT_TIMEOUT_MS)
    }

    private fun cancelConnectTimeout() {
        mainHandler.removeCallbacks(connectTimeoutRunnable)
    }

    private fun privateExportDirectoryForEntry(entry: PolarOfflineRecordingEntry): File {
        val root = File(appContext.filesDir, "polar_loop/exports/${sanitizeFileName(deviceId)}")
        return File(root, exportFolderName(entry))
    }

    private fun privateRawExportFile(entry: PolarOfflineRecordingEntry): File {
        val directory = privateExportDirectoryForEntry(entry)
        val baseName = sanitizeFileName(entry.path.substringAfterLast('/').ifBlank { "recording.raw" })
        val fileName = if (baseName.contains('.')) {
            "${baseName.substringBeforeLast('.')}.json"
        } else {
            "$baseName.json"
        }
        return File(directory, fileName)
    }

    private fun privateSummaryExportFile(entry: PolarOfflineRecordingEntry): File {
        return File(privateExportDirectoryForEntry(entry), "summary.json")
    }

    private fun isExportConfirmed(entry: PolarOfflineRecordingEntry): Boolean {
        return privateRawExportFile(entry).isFile && privateSummaryExportFile(entry).isFile
    }

    private fun exportFolderName(entry: PolarOfflineRecordingEntry): String {
        val baseName = sanitizeFileName(entry.path.substringAfterLast('/').ifBlank { "recording" })
        val digest = sha256(entry.path).take(12)
        return "${baseName}_$digest"
    }

    private fun publicExportRelativePath(entry: PolarOfflineRecordingEntry): String {
        return "${Environment.DIRECTORY_DOWNLOADS}/Polar Loop/${sanitizeFileName(deviceId)}/${exportFolderName(entry)}/"
    }

    private fun publicExportFilePath(entry: PolarOfflineRecordingEntry, fileName: String): String {
        val downloadsRoot = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS,
        )
        return File(
            downloadsRoot,
            "Polar Loop/${sanitizeFileName(deviceId)}/${exportFolderName(entry)}/$fileName",
        ).absolutePath
    }

    private fun writePublicExportFile(
        entry: PolarOfflineRecordingEntry,
        fileName: String,
        mimeType: String,
        content: String,
    ): String {
        val resolver = appContext.contentResolver
        val relativePath = publicExportRelativePath(entry)
        deletePublicExportFile(relativePath, fileName)
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Unable to create public export for $fileName")
        try {
            resolver.openOutputStream(uri)?.bufferedWriter(Charsets.UTF_8).use { writer ->
                writer?.write(content)
                    ?: throw IllegalStateException("Unable to open public export stream for $fileName")
            }
            val publishedValues = ContentValues().apply {
                put(MediaStore.MediaColumns.IS_PENDING, 0)
            }
            resolver.update(uri, publishedValues, null, null)
        } catch (error: Throwable) {
            resolver.delete(uri, null, null)
            throw error
        }
        return publicExportFilePath(entry, fileName)
    }

    private fun deletePublicExportFile(relativePath: String, fileName: String) {
        val resolver = appContext.contentResolver
        val selection = "${MediaStore.MediaColumns.RELATIVE_PATH} = ? AND ${MediaStore.MediaColumns.DISPLAY_NAME} = ?"
        val selectionArgs = arrayOf(relativePath, fileName)
        resolver.delete(MediaStore.Downloads.EXTERNAL_CONTENT_URI, selection, selectionArgs)
    }

    private fun sha256(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val bytes = digest.digest(value.toByteArray())
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun sanitizeFileName(value: String): String {
        return value.replace(Regex("[^A-Za-z0-9._-]"), "_")
    }

    private fun parseLocalDateTime(value: String): LocalDateTime {
        return runCatching { LocalDateTime.parse(value) }
            .getOrElse { OffsetDateTime.parse(value).toLocalDateTime() }
    }

    private fun emitConnection(state: String) {
        emit(mapOf("type" to "connection", "state" to state))
    }

    private fun emitError(scope: String, message: String, code: String? = null) {
        emit(
            mapOf(
                "type" to "error",
                "scope" to scope,
                "message" to message,
                "code" to code,
            ),
        )
    }

    private fun emit(payload: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(payload)
        }
    }

    private fun friendlyErrorMessage(error: Throwable): String {
        val message = error.message ?: "Polar Loop operation failed"
        return when {
            message.contains("NO_SUCH_FILE_OR_DIRECTORY") ->
                "Selected offline recording no longer exists on the device. Refresh recordings and try again."
            error.javaClass.simpleName == "PolarOperationNotSupported" ->
                "Polar Loop operation is not supported for the selected item or current device state. Refresh recordings and try again."
            else -> message
        }
    }

    private fun offlineRecordingDataPayload(data: PolarOfflineRecordingData): Map<String, Any?> {
        return when (data) {
            is PolarOfflineRecordingData.AccOfflineRecording -> linkedMapOf(
                "kind" to "ACC",
                "samples" to data.data.samples.map { sample ->
                    linkedMapOf(
                        "timestamp_ns" to sample.timeStamp,
                        "x" to sample.x,
                        "y" to sample.y,
                        "z" to sample.z,
                    )
                },
            )

            is PolarOfflineRecordingData.GyroOfflineRecording -> linkedMapOf(
                "kind" to "GYRO",
                "samples" to data.data.samples.map { sample ->
                    linkedMapOf(
                        "timestamp_ns" to sample.timeStamp,
                        "x" to sample.x,
                        "y" to sample.y,
                        "z" to sample.z,
                    )
                },
            )

            is PolarOfflineRecordingData.MagOfflineRecording -> linkedMapOf(
                "kind" to "MAGNETOMETER",
                "samples" to data.data.samples.map { sample ->
                    linkedMapOf(
                        "timestamp_ns" to sample.timeStamp,
                        "x" to sample.x,
                        "y" to sample.y,
                        "z" to sample.z,
                    )
                },
            )

            is PolarOfflineRecordingData.PpgOfflineRecording -> linkedMapOf(
                "kind" to "PPG",
                "ppg_type" to data.data.type.name,
                "samples" to data.data.samples.map { sample ->
                    linkedMapOf(
                        "timestamp_ns" to sample.timeStamp,
                        "channel_samples" to sample.channelSamples,
                        "status_bits" to sample.statusBits,
                    )
                },
            )

            is PolarOfflineRecordingData.PpiOfflineRecording -> linkedMapOf(
                "kind" to "PPI",
                "samples" to data.data.samples.map { sample ->
                    linkedMapOf(
                        "timestamp_ns" to sample.timeStamp.toLong(),
                        "ppi_ms" to sample.ppi,
                        "error_estimate_ms" to sample.errorEstimate,
                        "hr" to sample.hr,
                        "blocker_bit" to sample.blockerBit,
                        "skin_contact_status" to sample.skinContactStatus,
                        "skin_contact_supported" to sample.skinContactSupported,
                    )
                },
            )

            is PolarOfflineRecordingData.HrOfflineRecording -> linkedMapOf(
                "kind" to "HR",
                "samples" to data.data.samples.map { sample ->
                    linkedMapOf(
                        "hr" to sample.hr,
                        "rr_ms" to sample.rrsMs,
                    )
                },
            )

            is PolarOfflineRecordingData.TemperatureOfflineRecording -> linkedMapOf(
                "kind" to "TEMPERATURE",
                "samples" to data.data.samples.map { sample ->
                    linkedMapOf(
                        "timestamp_ns" to sample.timeStamp,
                        "temperature_c" to sample.temperature,
                    )
                },
            )

            is PolarOfflineRecordingData.SkinTemperatureOfflineRecording -> linkedMapOf(
                "kind" to "SKIN_TEMPERATURE",
                "samples" to data.data.samples.map { sample ->
                    linkedMapOf(
                        "timestamp_ns" to sample.timeStamp,
                        "temperature_c" to sample.temperature,
                    )
                },
            )
        }
    }

    private fun matches(identifier: String): Boolean {
        if (deviceId.isBlank()) return false
        if (identifier == deviceId) return true
        return identifier.uppercase().contains(deviceId.uppercase())
    }
}

private fun List<Int>.averageIntOrNull(): Double? {
    if (isEmpty()) return null
    return average()
}

private fun List<Float>.averageFloatOrNull(): Double? {
    if (isEmpty()) return null
    return map(Float::toDouble).average()
}
