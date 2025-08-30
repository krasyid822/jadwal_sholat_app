package jadwalsholat.rasyid

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkManager
import androidx.work.BackoffPolicy
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.loader.FlutterLoader
import android.os.Handler
import android.os.Looper
import java.util.concurrent.TimeUnit

class PrayerWidgetUpdateWorker(appContext: Context, params: WorkerParameters): CoroutineWorker(appContext, params) {
    companion object {
        private const val TAG = "PrayerWidgetUpdateWorker"
        const val METHOD_CHANNEL = "jadwalsholat.rasyid/widget_update"

        fun enqueueImmediate(context: Context) {
            val work = OneTimeWorkRequest.Builder(PrayerWidgetUpdateWorker::class.java)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build()
            WorkManager.getInstance(context).enqueue(work)
        }
    }

    override suspend fun doWork(): Result {
        var flutterEngine: FlutterEngine? = null
        try {
            // We'll initialize Flutter on the main thread. Use a latch to wait until
            // initialization + engine creation + Dart entrypoint execution have started.
            val initLatch = java.util.concurrent.CountDownLatch(1)

            // Set up completion latch and success flag (Dart side will call back)
            val completionLatch = java.util.concurrent.CountDownLatch(1)
            var success = false

            val flutterLoader = FlutterLoader()

            // Post initialization and engine startup to main thread
            Handler(Looper.getMainLooper()).post {
                try {
                    flutterLoader.startInitialization(applicationContext)
                    flutterLoader.ensureInitializationComplete(applicationContext, arrayOf())

                    flutterEngine = FlutterEngine(applicationContext)

                    // Set up a method channel to listen for completion
                    val channel = MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, METHOD_CHANNEL)
                    channel.setMethodCallHandler { call, result ->
                        when (call.method) {
                            "updateComplete" -> {
                                success = true
                                result.success(null)
                                completionLatch.countDown()
                            }
                            "updateFailed" -> {
                                val msg = call.arguments as? String
                                Log.w(TAG, "Dart update failed: $msg")
                                result.success(null)
                                completionLatch.countDown()
                            }
                            else -> result.notImplemented()
                        }
                    }

                    // Execute the Dart entrypoint defined in Flutter code
                    val appBundlePath = flutterLoader.findAppBundlePath()
                    val entrypoint = DartEntrypoint(appBundlePath, "widgetBackgroundEntrypoint")
                    flutterEngine!!.dartExecutor.executeDartEntrypoint(entrypoint)
                } catch (t: Throwable) {
                    Log.w(TAG, "Initialization on main thread failed: ${t.message}")
                    // ensure completion latch doesn't wait forever
                    completionLatch.countDown()
                } finally {
                    initLatch.countDown()
                }
            }

            // Wait until main-thread init has at least started
            if (!initLatch.await(10, TimeUnit.SECONDS)) {
                Log.w(TAG, "Flutter initialization did not complete in time on main thread")
                return Result.retry()
            }

            // Wait up to 30s for Dart code to signal completion
            if (!completionLatch.await(30, TimeUnit.SECONDS)) {
                Log.w(TAG, "Timed out waiting for Dart update completion")
                return Result.retry()
            }

            return if (success) Result.success() else Result.retry()
        } catch (e: Exception) {
            Log.w(TAG, "PrayerWidgetUpdateWorker failed: ${e.message}")
            return Result.retry()
        } finally {
            try {
                flutterEngine?.destroy()
            } catch (_: Exception) {}
        }
    }
}
