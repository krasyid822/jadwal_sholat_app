package jadwalsholat.rasyid

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

object HealthProbeHelper {
    private const val HEALTH_CHANNEL = "jadwalsholat.rasyid/health_probe"

    /**
     * Try direct probe into Flutter via MethodChannel. Returns true if Flutter replies within timeout.
     */
    fun probeFlutterDirect(context: Context, timeoutSeconds: Long = 5): Boolean {
        try {
            val engine: FlutterEngine? = MainActivity.flutterEngineInstance
            if (engine == null) {
                return false
            }

            val latch = CountDownLatch(1)
            var resultOk = false

            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, HEALTH_CHANNEL)
            channel.invokeMethod("probe", null, object: MethodChannel.Result {
                override fun success(result: Any?) {
                    resultOk = true
                    latch.countDown()
                }

                // Match the expected signature: error(code: String, message: String?, details: Any?)
                override fun error(code: String, message: String?, details: Any?) {
                    latch.countDown()
                }

                override fun notImplemented() {
                    latch.countDown()
                }
            })

            latch.await(timeoutSeconds, TimeUnit.SECONDS)
            return resultOk
        } catch (e: Exception) {
            return false
        }
    }

    /**
     * Fallback: get last heartbeat timestamp saved by Flutter
     */
    fun getLastHeartbeatMs(context: Context): Long {
        val prefs = context.getSharedPreferences("jadwalsholat_prefs", Context.MODE_PRIVATE)
        return prefs.getLong("flutter_last_heartbeat_ms", 0L)
    }
}
