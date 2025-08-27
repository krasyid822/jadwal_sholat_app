package jadwalsholat.rasyid

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import java.io.IOException

object AndroidAudioHelper {
    private var mediaPlayer: MediaPlayer? = null

    fun playAssetAsRingtone(context: Context, assetPath: String) {
        stop()
        try {
            val afd = context.assets.openFd(assetPath)
            mediaPlayer = MediaPlayer()
            mediaPlayer?.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            afd.close()
            mediaPlayer?.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
                    // Respect loop setting stored in Android SharedPreferences.
                    // Flutter side saves boolean 'loop_adhan_audio' (default false).
                    try {
                        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        // Flutter stores values with key style: "flutter." + actualKey
                        val stored = prefs.getString("flutter.loop_adhan_audio", null)
                        val loop = when (stored) {
                            null -> false
                            "true" -> true
                            "false" -> false
                            else -> false
                        }
                        mediaPlayer?.isLooping = loop
                    } catch (e: Exception) {
                        // Fallback: don't loop
                        mediaPlayer?.isLooping = false
                    }
            mediaPlayer?.prepare()
            mediaPlayer?.start()
        } catch (e: IOException) {
            stop()
            throw e
        }
    }

    // Play a sound from android raw resources by resource name (without extension)
    fun playRawResourceAsRingtone(context: Context, resName: String) {
        stop()
        try {
            val resId = context.resources.getIdentifier(resName, "raw", context.packageName)
            if (resId == 0) throw IOException("Resource not found: $resName")
            val afd = context.resources.openRawResourceFd(resId)
            if (afd == null) throw IOException("Unable to open resource fd: $resName")
            mediaPlayer = MediaPlayer()
            mediaPlayer?.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            afd.close()
            mediaPlayer?.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            try {
                val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val stored = prefs.getString("flutter.loop_adhan_audio", null)
                val loop = when (stored) {
                    null -> false
                    "true" -> true
                    "false" -> false
                    else -> false
                }
                mediaPlayer?.isLooping = loop
            } catch (e: Exception) {
                mediaPlayer?.isLooping = false
            }
            mediaPlayer?.prepare()
            mediaPlayer?.start()
        } catch (e: IOException) {
            stop()
            throw e
        }
    }

    fun playOnce(context: Context, assetPath: String) {
        try {
            val afd = context.assets.openFd(assetPath)
            val player = MediaPlayer()
            player.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            afd.close()
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            player.isLooping = false
            player.prepare()
            player.setOnCompletionListener { p ->
                p.release()
            }
            player.start()
        } catch (e: IOException) {
            throw e
        }
    }

    // Play a short sound from raw resources once
    fun playRawOnce(context: Context, resName: String) {
        val resId = context.resources.getIdentifier(resName, "raw", context.packageName)
        if (resId == 0) throw IOException("Resource not found: $resName")
        val afd = context.resources.openRawResourceFd(resId) ?: throw IOException("Unable to open resource fd: $resName")
        val player = MediaPlayer()
        player.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
        afd.close()
        player.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        )
        player.isLooping = false
        player.setOnCompletionListener { p -> p.release() }
        player.prepare()
        player.start()
    }

    fun stop() {
        try {
            mediaPlayer?.stop()
            mediaPlayer?.reset()
            mediaPlayer?.release()
        } catch (e: Exception) {
            // ignore
        } finally {
            mediaPlayer = null
        }
    }
}
