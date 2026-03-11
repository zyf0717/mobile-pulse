package com.example.mobile_pulse

import android.content.Context
import com.polar.androidcommunications.api.ble.model.DisInfo
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
import io.reactivex.rxjava3.disposables.Disposable
import java.time.Instant

class PolarPacerChannelHandler(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val METHOD_CHANNEL = "com.example.mobile_pulse/polar_pacer/methods"
        private const val EVENT_CHANNEL = "com.example.mobile_pulse/polar_pacer/events"
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

    private var eventSink: EventChannel.EventSink? = null
    private var deviceId: String = ""
    private var connectedIdentifier: String? = null
    private var onlineStreamingReady = false
    private var shouldStartAcc = false
    private var shouldStartPpi = false
    private var accDisposable: Disposable? = null
    private var ppiDisposable: Disposable? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        api.setApiCallback(object : PolarBleApiCallback() {
            override fun deviceConnecting(polarDeviceInfo: PolarDeviceInfo) {
                if (matches(polarDeviceInfo.deviceId)) emitConnection("connecting")
            }

            override fun deviceConnected(polarDeviceInfo: PolarDeviceInfo) {
                if (!matches(polarDeviceInfo.deviceId)) return
                connectedIdentifier = polarDeviceInfo.deviceId
                emitConnection("connected")
            }

            override fun deviceDisconnected(polarDeviceInfo: PolarDeviceInfo) {
                if (!matches(polarDeviceInfo.deviceId)) return
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
                if (feature == PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_ONLINE_STREAMING) {
                    onlineStreamingReady = true
                    startPendingStreams()
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
                deviceId = nextDeviceId
                emitConnection("connecting")
                api.connectToDevice(deviceId)
                result.success(null)
            }

            "disconnect" -> {
                stopStreams()
                connectedIdentifier?.let(api::disconnectFromDevice)
                connectedIdentifier = null
                onlineStreamingReady = false
                result.success(null)
            }

            "startAccStreaming" -> {
                shouldStartAcc = true
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
        stopStreams()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    private fun startPendingStreams() {
        val identifier = connectedIdentifier ?: return
        if (!onlineStreamingReady) return

        if (shouldStartAcc && accDisposable == null) {
            accDisposable = api.requestStreamSettings(
                identifier,
                PolarBleApi.PolarDeviceDataType.ACC,
            )
                .flatMapPublisher { settings -> api.startAccStreaming(identifier, settings) }
                .subscribe(
                    { data ->
                        emit(
                            mapOf(
                                "type" to "acc",
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
                    },
                    { error ->
                        emitConnection("error")
                        emit(mapOf("type" to "error", "message" to (error.message ?: "ACC stream failed")))
                    },
                )
        }

        if (shouldStartPpi && ppiDisposable == null) {
            ppiDisposable = api.startPpiStreaming(identifier)
                .subscribe(
                    { data: PolarPpiData ->
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
                    },
                    { error ->
                        emitConnection("error")
                        emit(mapOf("type" to "error", "message" to (error.message ?: "PPI stream failed")))
                    },
                )
        }
    }

    private fun stopStreams() {
        stopAccStream()
        stopPpiStream()
    }

    private fun stopAccStream() {
        accDisposable?.dispose()
        accDisposable = null
    }

    private fun stopPpiStream() {
        ppiDisposable?.dispose()
        ppiDisposable = null
    }

    private fun emitConnection(state: String) {
        emit(mapOf("type" to "connection", "state" to state))
    }

    private fun emit(payload: Map<String, Any?>) {
        eventSink?.success(payload)
    }

    private fun matches(identifier: String): Boolean {
        if (deviceId.isBlank()) return false
        if (identifier == deviceId) return true
        return identifier.uppercase().contains(deviceId.uppercase())
    }
}
