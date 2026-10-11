package com.mfficiency.best_todo_2

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build

// Whether sound would go anywhere but the phone itself — shared by the
// "Play out loud?" guard in Dart (channel `besttodo/audio_output` in
// MainActivity) and the widgets' native MusicPlayGuardActivity.
object AudioOutputs {
    fun isExternalConnected(context: Context): Boolean {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val builtIn = setOf(
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE,
            AudioDeviceInfo.TYPE_TELEPHONY,
            AudioDeviceInfo.TYPE_UNKNOWN,
            AudioDeviceInfo.TYPE_REMOTE_SUBMIX,
        ) + (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
            setOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE) else emptySet())
        return audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            .any { it.type !in builtIn }
    }
}
