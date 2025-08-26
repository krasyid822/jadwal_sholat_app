package jadwalsholat.rasyid

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class StopAudioReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("StopAudioReceiver", "Received stop audio request")
        try {
            AndroidAudioHelper.stop()
            Log.d("StopAudioReceiver", "Audio stopped by user action")
        } catch (e: Exception) {
            Log.e("StopAudioReceiver", "Failed to stop audio: ${e.message}")
        }
    }
}
