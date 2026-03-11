package com.example.mobile_pulse

import android.app.ActivityManager
import android.net.TrafficStats
import android.os.Build
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "com.example.mobile_pulse/device_metrics"
    }

    private var polarPacerChannelHandler: PolarPacerChannelHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSnapshot" -> result.success(buildSnapshot())
                    else -> result.notImplemented()
                }
            }
        polarPacerChannelHandler = PolarPacerChannelHandler(
            context = applicationContext,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun onDestroy() {
        polarPacerChannelHandler?.dispose()
        polarPacerChannelHandler = null
        super.onDestroy()
    }

    private fun buildSnapshot(): Map<String, Any?> {
        // ── Memory ──────────────────────────────────────────────────────────
        // ActivityManager.getMemoryInfo() is the standard public API;
        // no permission required.
        val am = getSystemService(ActivityManager::class.java)
        val mi = ActivityManager.MemoryInfo()
        am.getMemoryInfo(mi)

        // ── Thermal ─────────────────────────────────────────────────────────
        // PowerManager.getCurrentThermalStatus() → int 0–6 (API 29).
        // PowerManager.getThermalHeadroom(0)     → float 0.0–1.0 (API 30).
        // No permission required for either.
        val pm = getSystemService(PowerManager::class.java)
        val thermalStatus = pm.currentThermalStatus
        val thermalHeadroom: Double? = if (Build.VERSION.SDK_INT >= 30) {
            val h = pm.getThermalHeadroom(0)
            if (h.isNaN()) null else h.toDouble()
        } else null

        // ── Network ─────────────────────────────────────────────────────────
        // TrafficStats gives cumulative bytes since boot; delta is computed
        // in Dart between successive snapshots. No permission required (API 8).
        return mapOf(
            "totalMemBytes"  to mi.totalMem,
            "availMemBytes"  to mi.availMem,
            "rxBytesTotal"   to TrafficStats.getTotalRxBytes(),
            "txBytesTotal"   to TrafficStats.getTotalTxBytes(),
            "thermalStatus"  to thermalStatus,
            "thermalHeadroom" to thermalHeadroom,
        )
    }
}
