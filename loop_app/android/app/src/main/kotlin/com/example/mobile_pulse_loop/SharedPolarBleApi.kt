package com.example.mobile_pulse_loop

import android.content.Context
import com.polar.androidcommunications.api.ble.model.DisInfo
import com.polar.sdk.api.PolarBleApi
import com.polar.sdk.api.PolarBleApiCallback
import com.polar.sdk.api.PolarBleApiDefaultImpl
import com.polar.sdk.api.model.PolarDeviceInfo
import com.polar.sdk.api.model.PolarHealthThermometerData
import com.polar.sdk.api.model.PolarHrData

class SharedPolarBleApi(context: Context) {

    val appContext: Context = context.applicationContext

    interface Listener {
        fun deviceConnecting(polarDeviceInfo: PolarDeviceInfo) {}
        fun deviceConnected(polarDeviceInfo: PolarDeviceInfo) {}
        fun deviceDisconnected(polarDeviceInfo: PolarDeviceInfo) {}
        fun bleSdkFeatureReady(
            identifier: String,
            feature: PolarBleApi.PolarBleSdkFeature,
        ) {
        }

        fun hrNotificationReceived(
            identifier: String,
            data: PolarHrData.PolarHrSample,
        ) {
        }

        fun disInformationReceived(identifier: String, disInfo: DisInfo) {}
        fun htsNotificationReceived(identifier: String, data: PolarHealthThermometerData) {}
    }

    val api: PolarBleApi = PolarBleApiDefaultImpl.defaultImplementation(
        appContext,
        setOf(
            PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_DEVICE_TIME_SETUP,
            PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_OFFLINE_RECORDING,
            PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_FILE_TRANSFER,
            PolarBleApi.PolarBleSdkFeature.FEATURE_POLAR_SDK_MODE,
        ),
    )

    private val listeners = linkedSetOf<Listener>()

    init {
        api.setApiCallback(object : PolarBleApiCallback() {
            override fun deviceConnecting(polarDeviceInfo: PolarDeviceInfo) {
                snapshotListeners().forEach { it.deviceConnecting(polarDeviceInfo) }
            }

            override fun deviceConnected(polarDeviceInfo: PolarDeviceInfo) {
                snapshotListeners().forEach { it.deviceConnected(polarDeviceInfo) }
            }

            override fun deviceDisconnected(polarDeviceInfo: PolarDeviceInfo) {
                snapshotListeners().forEach { it.deviceDisconnected(polarDeviceInfo) }
            }

            override fun bleSdkFeatureReady(
                identifier: String,
                feature: PolarBleApi.PolarBleSdkFeature,
            ) {
                snapshotListeners().forEach { it.bleSdkFeatureReady(identifier, feature) }
            }

            override fun hrNotificationReceived(
                identifier: String,
                data: PolarHrData.PolarHrSample,
            ) {
                snapshotListeners().forEach { it.hrNotificationReceived(identifier, data) }
            }

            override fun disInformationReceived(identifier: String, disInfo: DisInfo) {
                snapshotListeners().forEach { it.disInformationReceived(identifier, disInfo) }
            }

            override fun htsNotificationReceived(
                identifier: String,
                data: PolarHealthThermometerData,
            ) {
                snapshotListeners().forEach { it.htsNotificationReceived(identifier, data) }
            }
        })
    }

    fun addListener(listener: Listener) {
        synchronized(listeners) {
            listeners.add(listener)
        }
    }

    fun removeListener(listener: Listener) {
        synchronized(listeners) {
            listeners.remove(listener)
        }
    }

    fun shutDown() {
        synchronized(listeners) {
            listeners.clear()
        }
        api.shutDown()
    }

    private fun snapshotListeners(): List<Listener> {
        return synchronized(listeners) {
            listeners.toList()
        }
    }
}
