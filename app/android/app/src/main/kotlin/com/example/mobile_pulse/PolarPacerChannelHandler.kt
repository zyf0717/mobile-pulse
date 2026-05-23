package com.example.mobile_pulse

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.polar.androidcommunications.api.ble.model.DisInfo
import com.polar.androidcommunications.api.ble.model.gatt.client.pmd.PmdMeasurementType
import com.polar.sdk.api.PolarBleApi
import com.polar.sdk.api.PolarBleApiCallback
import com.polar.sdk.api.PolarBleApiDefaultImpl
import com.polar.sdk.api.model.PolarDeviceInfo
import com.polar.sdk.api.model.PolarHealthThermometerData
import com.polar.sdk.api.model.PolarHrData
import com.polar.sdk.api.model.PolarPpiData
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.time.Instant

// Version-pinned notes for this bridge:
// - Gradle currently depends on com.github.polarofficial:polar-ble-sdk:6.15.0.
// - Product/watch behavior was cross-checked against the official repo docs:
//   documentation/products/PolarPacerAndPacerPro.md
//   documentation/UsingSDKWithWatches.md
// - API surface was validated against the 6.15.0 AAR we actually compile, not
//   just the repo's master-branch examples. That matters because the generated
//   docs/examples and the shipped callback signatures can drift.
//
// If the SDK version changes, re-check at least:
// - PolarBleApiCallback abstract methods
// - PolarBleApi.PolarDeviceDataType enum location
// - PolarPpiData.PolarPpiSample property names/types
// - watch setup requirements for SDK Share / exercise wait mode
class PolarPacerChannelHandler(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val METHOD_CHANNEL = "com.example.mobile_pulse/polar_pacer/methods"
        private const val EVENT_CHANNEL = "com.example.mobile_pulse/polar_pacer/events"
        private const val INITIAL_STREAM_START_DELAY_MS = 2_000L
        private const val STREAM_RETRY_BASE_DELAY_MS = 2_000L
        private const val STREAM_RETRY_MAX_DELAY_MS = 10_000L
    }

    private val api: PolarBleApi = PolarBleApiDefaultImpl.defaultImplementation(
        context.applicationContext,
        setOf(
            PolarBleApi.PolarBleSdkFeature.FEATURE_HR,
            PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_ONLINE_STREAMING,
        ),
    )

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val connectTimeoutRunnable = Runnable {
        if (connectedIdentifier != null || deviceId.isBlank()) return@Runnable
        emitConnection("error")
        emit(
            mapOf(
                "type" to "error",
                "scope" to "connection",
                "message" to "Timed out waiting for Polar Pacer $deviceId. " +
                    "Verify the watch is nearby, paired, and advertising with SDK Share enabled.",
            ),
        )
    }
    private val accStartRunnable = Runnable {
        if (shouldStartAcc && accJob == null && onlineStreamingReady) {
            startAccStream()
        }
    }
    private val ppiStartRunnable = Runnable {
        if (shouldStartPpi && ppiJob == null && onlineStreamingReady) {
            startPpiStream()
        }
    }

    private var eventSink: EventChannel.EventSink? = null
    private var deviceId: String = ""
    private var connectedIdentifier: String? = null
    private var onlineStreamingReady = false
    private var shouldStartAcc = false
    private var shouldStartPpi = false
    private var accJob: Job? = null
    private var ppiJob: Job? = null
    private var accRetryAttempt = 0
    private var ppiRetryAttempt = 0

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        api.setApiCallback(object : PolarBleApiCallback() {
            // In the 6.15.0 artifact these two callbacks are abstract and must
            // be implemented even though this app does not use DIS/HTS data.
            override fun deviceConnecting(polarDeviceInfo: PolarDeviceInfo) {
                if (!matches(polarDeviceInfo.deviceId)) return
                cancelConnectTimeout()
                emitConnection("connecting")
            }

            override fun deviceConnected(polarDeviceInfo: PolarDeviceInfo) {
                if (!matches(polarDeviceInfo.deviceId)) return
                cancelConnectTimeout()
                connectedIdentifier = polarDeviceInfo.deviceId
                emitConnection("connected")
            }

            override fun deviceDisconnected(polarDeviceInfo: PolarDeviceInfo) {
                if (!matches(polarDeviceInfo.deviceId)) return
                cancelConnectTimeout()
                stopStreams()
                connectedIdentifier = null
                onlineStreamingReady = false
                emitConnection("disconnected")
            }

            override fun bleSdkFeatureReady(
                identifier: String,
                feature: PolarBleApi.PolarBleSdkFeature,
            ) {
                if (!matches(identifier)) return
                connectedIdentifier = identifier
                // Official watch docs say online streams become usable only
                // after SDK Share is enabled on-watch and the watch is in an
                // exercise wait view. FEATURE_POLAR_ONLINE_STREAMING becoming
                // ready is our gate before requesting ACC/PPI streams.
                if (feature == PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_ONLINE_STREAMING) {
                    onlineStreamingReady = true
                    startPendingStreams(INITIAL_STREAM_START_DELAY_MS)
                }
            }

            override fun hrNotificationReceived(
                identifier: String,
                data: PolarHrData.PolarHrSample,
            ) {
                if (!matches(identifier)) return
                emit(
                    mapOf(
                        "type" to "hr",
                        "bpm" to data.hr,
                        "rr_ms" to data.rrsMs,
                        "timestamp" to Instant.now().toString(),
                    ),
                )
            }

            override fun disInformationReceived(identifier: String, disInfo: DisInfo) {
                // Not used by the app.
            }

            override fun htsNotificationReceived(
                identifier: String,
                data: PolarHealthThermometerData,
            ) {
                // Not used by the app.
            }
        })
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
                    result.error("missing_device_id", "POLAR_PACER_DEVICE_ID is not set", null)
                    return
                }
                stopStreams()
                connectedIdentifier = null
                onlineStreamingReady = false
                deviceId = nextDeviceId
                emitConnection("scanning")
                api.connectToDevice(deviceId)
                scheduleConnectTimeout()
                result.success(null)
            }

            "disconnect" -> {
                cancelConnectTimeout()
                stopStreams()
                connectedIdentifier?.let(api::disconnectFromDevice)
                connectedIdentifier = null
                onlineStreamingReady = false
                result.success(null)
            }

            "startAccStreaming" -> {
                shouldStartAcc = true
                accRetryAttempt = 0
                startPendingStreams()
                result.success(null)
            }

            "stopAccStreaming" -> {
                shouldStartAcc = false
                stopAccStream()
                result.success(null)
            }

            "startPpiStreaming" -> {
                shouldStartPpi = true
                ppiRetryAttempt = 0
                startPendingStreams()
                result.success(null)
            }

            "stopPpiStreaming" -> {
                shouldStartPpi = false
                stopPpiStream()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    fun dispose() {
        cancelConnectTimeout()
        stopStreams()
        scope.cancel()
        api.shutDown()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    private fun startPendingStreams(delayMs: Long = 0L) {
        if (connectedIdentifier == null || !onlineStreamingReady) return

        if (shouldStartAcc && accJob == null) {
            scheduleAccStart(delayMs)
        }

        if (shouldStartPpi && ppiJob == null) {
            schedulePpiStart(delayMs)
        }
    }

    private fun stopStreams() {
        stopAccStream()
        stopPpiStream()
    }

    private fun stopAccStream(resetRetryAttempt: Boolean = true) {
        cancelAccStart()
        accJob?.cancel()
        accJob = null
        connectedIdentifier?.let { identifier ->
            runCatching { api.stopStreaming(identifier, PmdMeasurementType.ACC) }
        }
        if (resetRetryAttempt) {
            accRetryAttempt = 0
        }
    }

    private fun stopPpiStream(resetRetryAttempt: Boolean = true) {
        cancelPpiStart()
        ppiJob?.cancel()
        ppiJob = null
        connectedIdentifier?.let { identifier ->
            runCatching { api.stopStreaming(identifier, PmdMeasurementType.PPI) }
        }
        if (resetRetryAttempt) {
            ppiRetryAttempt = 0
        }
    }

    private fun scheduleConnectTimeout() {
        cancelConnectTimeout()
        mainHandler.postDelayed(connectTimeoutRunnable, 15_000)
    }

    private fun cancelConnectTimeout() {
        mainHandler.removeCallbacks(connectTimeoutRunnable)
    }

    private fun startAccStream() {
        val identifier = connectedIdentifier ?: return
        if (!onlineStreamingReady || !shouldStartAcc || accJob != null) return
        accJob = scope.launch {
            try {
                val settings = api.requestStreamSettings(
                    identifier,
                    PolarBleApi.PolarDeviceDataType.ACC,
                )
                api.startAccStreaming(identifier, settings).collect { data ->
                    accRetryAttempt = 0
                    emit(
                        mapOf(
                            "type" to "acc",
                            // Polar's Pacer/Pacer Pro product guide documents
                            // ACC as 50 Hz, 8 G, axis values in mG.
                            "sample_rate_hz" to 50,
                            "samples_mg" to data.samples.map { sample ->
                                mapOf(
                                    "x_mg" to sample.x,
                                    "y_mg" to sample.y,
                                    "z_mg" to sample.z,
                                )
                            },
                            "timestamp" to Instant.now().toString(),
                        ),
                    )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                stopAccStream(resetRetryAttempt = false)
                scheduleAccRetry(error.message ?: "ACC stream failed")
            } finally {
                if (accJob?.isCancelled != false) {
                    accJob = null
                }
            }
        }
    }

    private fun startPpiStream() {
        val identifier = connectedIdentifier ?: return
        if (!onlineStreamingReady || !shouldStartPpi || ppiJob != null) return
        ppiJob = scope.launch {
            try {
                api.startPpiStreaming(identifier).collect { data: PolarPpiData ->
                    ppiRetryAttempt = 0
                    emit(
                        mapOf(
                            "type" to "ppi",
                            "samples" to data.samples.map { sample ->
                                mapOf(
                                    "ppi_ms" to sample.ppi.toInt(),
                                    "error_estimate_ms" to sample.errorEstimate.toInt(),
                                    "hr" to sample.hr,
                                    "blocker_bit" to sample.blockerBit,
                                    "skin_contact_status" to sample.skinContactStatus,
                                    "skin_contact_supported" to sample.skinContactSupported,
                                    "timestamp_ns" to sample.timeStamp.toLong(),
                                )
                            },
                            "timestamp" to Instant.now().toString(),
                        ),
                    )
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                stopPpiStream(resetRetryAttempt = false)
                schedulePpiRetry(error.message ?: "PPI stream failed")
            } finally {
                if (ppiJob?.isCancelled != false) {
                    ppiJob = null
                }
            }
        }
    }

    private fun scheduleAccStart(delayMs: Long) {
        cancelAccStart()
        if (!shouldStartAcc || accJob != null || !onlineStreamingReady) return
        mainHandler.postDelayed(accStartRunnable, delayMs)
    }

    private fun schedulePpiStart(delayMs: Long) {
        cancelPpiStart()
        if (!shouldStartPpi || ppiJob != null || !onlineStreamingReady) return
        mainHandler.postDelayed(ppiStartRunnable, delayMs)
    }

    private fun cancelAccStart() {
        mainHandler.removeCallbacks(accStartRunnable)
    }

    private fun cancelPpiStart() {
        mainHandler.removeCallbacks(ppiStartRunnable)
    }

    private fun scheduleAccRetry(message: String) {
        if (!shouldStartAcc || connectedIdentifier == null || !onlineStreamingReady) return
        val delayMs = nextRetryDelayMs(accRetryAttempt)
        accRetryAttempt += 1
        emitStreamRetry("acc", message, delayMs)
        scheduleAccStart(delayMs)
    }

    private fun schedulePpiRetry(message: String) {
        if (!shouldStartPpi || connectedIdentifier == null || !onlineStreamingReady) return
        val delayMs = nextRetryDelayMs(ppiRetryAttempt)
        ppiRetryAttempt += 1
        emitStreamRetry("ppi", message, delayMs)
        schedulePpiStart(delayMs)
    }

    private fun nextRetryDelayMs(attempt: Int): Long {
        val multiplier = 1L shl attempt.coerceAtMost(4)
        return (STREAM_RETRY_BASE_DELAY_MS * multiplier).coerceAtMost(STREAM_RETRY_MAX_DELAY_MS)
    }

    private fun emitStreamRetry(stream: String, message: String, retryDelayMs: Long) {
        emit(
            mapOf(
                "type" to "error",
                "scope" to "stream",
                "stream" to stream,
                "retry_in_ms" to retryDelayMs,
                "message" to "${streamErrorMessage(message)} Retrying in ${retryDelayMs / 1000}s.",
            ),
        )
    }

    private fun emitConnection(state: String) {
        emit(mapOf("type" to "connection", "state" to state))
    }

    private fun emit(payload: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(payload)
        }
    }

    private fun streamErrorMessage(message: String): String {
        return if (message.contains("ERROR_INVALID_STATE")) {
            "$message. On Polar Pacer, enable SDK Share on the watch and stay on an exercise wait screen before starting ACC/PPI."
        } else {
            message
        }
    }

    private fun matches(identifier: String): Boolean {
        if (deviceId.isBlank()) return false
        if (identifier == deviceId) return true
        // Polar watch identifiers may include more than the 8-char device id,
        // so we allow the configured id to match as an uppercase substring.
        return identifier.uppercase().contains(deviceId.uppercase())
    }
}
