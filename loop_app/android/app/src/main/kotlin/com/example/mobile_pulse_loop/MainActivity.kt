package com.example.mobile_pulse_loop

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var polarLoopChannelHandler: PolarLoopChannelHandler? = null
    private var sharedPolarBleApi: SharedPolarBleApi? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sharedPolarBleApi = SharedPolarBleApi(applicationContext)
        polarLoopChannelHandler = PolarLoopChannelHandler(
            sharedPolarBleApi = sharedPolarBleApi!!,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun onDestroy() {
        polarLoopChannelHandler?.dispose()
        polarLoopChannelHandler = null
        sharedPolarBleApi?.shutDown()
        sharedPolarBleApi = null
        super.onDestroy()
    }
}
