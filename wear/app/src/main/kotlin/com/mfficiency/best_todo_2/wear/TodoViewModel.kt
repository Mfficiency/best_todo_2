package com.mfficiency.best_todo_2.wear

import android.app.Application
import android.content.Context
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.mfficiency.best_todo_2.wear.core.AlarmRow
import com.mfficiency.best_todo_2.wear.core.Connection
import com.mfficiency.best_todo_2.wear.core.Labels
import com.mfficiency.best_todo_2.wear.core.Paths
import com.mfficiency.best_todo_2.wear.core.Payloads
import com.mfficiency.best_todo_2.wear.core.Pending
import com.mfficiency.best_todo_2.wear.core.PendingDone
import com.mfficiency.best_todo_2.wear.core.TodayPayload
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class UiState(
    val today: TodayPayload? = null,
    val todayAt: Long? = null,
    val alarms: List<AlarmRow>? = null,
    val alarmsAt: Long? = null,
    val pending: List<PendingDone> = emptyList(),
    val connection: Connection = Connection.CHECKING,
    val loading: Boolean = false,
    /** A string resource with the last error, null when fine. */
    val error: Int? = null,
)

/**
 * The watch's whole state: the phone's last lists (cached in
 * SharedPreferences, so the watch works without the phone), the "done" taps
 * not yet confirmed by the phone, and the connection. Only works while the
 * activity is started ([onStart]/[onStop], see MainActivity): no service, no
 * background work.
 */
class TodoViewModel(app: Application) : AndroidViewModel(app) {
    private val link = PhoneLink(app)
    private val prefs = app.getSharedPreferences("wear_cache", Context.MODE_PRIVATE)
    private val _state = MutableStateFlow(loadCache())
    val state: StateFlow<UiState> = _state.asStateFlow()
    private var listening = false

    private val listener = DataClient.OnDataChangedListener { events ->
        try {
            for (event in events) {
                if (event.type != DataEvent.TYPE_CHANGED) continue
                val snapshot = PhoneLink.snapshotOf(event.dataItem) ?: continue
                onSnapshot(snapshot)
            }
        } catch (e: Exception) {
            Log.w(TAG, "data change: $e")
        }
    }

    fun onStart() {
        if (!listening) {
            try {
                link.addListener(listener)
                listening = true
            } catch (e: Exception) {
                Log.w(TAG, "addListener: $e")
            }
        }
        refresh()
    }

    fun onStop() {
        if (listening) {
            try {
                link.removeListener(listener)
            } catch (e: Exception) {
                Log.w(TAG, "removeListener: $e")
            }
            listening = false
        }
    }

    /** Re-reads the phone's items, re-checks the phone, resends open taps. */
    fun refresh() {
        if (_state.value.loading) return
        _state.update { it.copy(loading = true) }
        viewModelScope.launch {
            var error: Int? = null
            try {
                for (snapshot in link.readItems()) onSnapshot(snapshot)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w(TAG, "readItems: $e")
                error = R.string.error_read
            }
            if (checkConnectionNow() && !resendUndelivered()) {
                error = R.string.error_send
            }
            _state.update { it.copy(loading = false, error = error) }
        }
    }

    /** The 30 s connection check while the screen is on. */
    fun checkConnection() {
        viewModelScope.launch {
            if (checkConnectionNow()) resendUndelivered()
        }
    }

    /** Marks [taskId] done here and tells the phone. */
    fun complete(taskId: String) {
        val now = System.currentTimeMillis()
        savePending(Pending.add(_state.value.pending, taskId, now))
        viewModelScope.launch {
            val sent = send(taskId)
            _state.update { it.copy(error = if (sent) null else R.string.error_send) }
        }
    }

    private suspend fun checkConnectionNow(): Boolean {
        return try {
            val capable = link.phoneNode() != null
            val any = if (capable) true else link.anyPhoneConnected()
            _state.update { it.copy(connection = Labels.connection(capable, any)) }
            capable
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "connection: $e")
            _state.update { it.copy(connection = Connection.UNREACHABLE) }
            false
        }
    }

    /** False when a resend failed. */
    private suspend fun resendUndelivered(): Boolean {
        var ok = true
        for (p in Pending.undelivered(_state.value.pending)) {
            if (!send(p.id)) ok = false
        }
        return ok
    }

    private suspend fun send(taskId: String): Boolean {
        return try {
            val node = link.phoneNode()
            if (node == null) {
                _state.update { it.copy(connection = Connection.UNREACHABLE) }
                return false
            }
            link.sendComplete(node.id, taskId)
            savePending(Pending.markDelivered(_state.value.pending, taskId))
            _state.update { it.copy(connection = Connection.CONNECTED) }
            true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "send: $e")
            false
        }
    }

    private fun onSnapshot(s: Snapshot) {
        when (s.path) {
            Paths.TODAY -> {
                val parsed = Payloads.parseToday(s.json) ?: return
                if (s.at < (_state.value.todayAt ?: 0L)) return
                _state.update { it.copy(today = parsed, todayAt = s.at) }
                prefs.edit().putString(KEY_TODAY, s.json).putLong(KEY_TODAY_AT, s.at).apply()
                savePending(_state.value.pending)
            }
            Paths.ALARMS -> {
                val parsed = Payloads.parseAlarms(s.json) ?: return
                if (s.at < (_state.value.alarmsAt ?: 0L)) return
                _state.update { it.copy(alarms = parsed, alarmsAt = s.at) }
                prefs.edit().putString(KEY_ALARMS, s.json).putLong(KEY_ALARMS_AT, s.at).apply()
            }
        }
    }

    /** Stores [list] after dropping what the phone's list already settled. */
    private fun savePending(list: List<PendingDone>) {
        val pruned = Pending.prune(list, _state.value.todayAt, System.currentTimeMillis())
        _state.update { it.copy(pending = pruned) }
        prefs.edit().putString(KEY_PENDING, Pending.toJson(pruned)).apply()
    }

    private fun loadCache(): UiState {
        return try {
            val todayAt = prefs.getLong(KEY_TODAY_AT, 0L).takeIf { it > 0L }
            val alarmsAt = prefs.getLong(KEY_ALARMS_AT, 0L).takeIf { it > 0L }
            UiState(
                today = Payloads.parseToday(prefs.getString(KEY_TODAY, null)),
                todayAt = todayAt,
                alarms = Payloads.parseAlarms(prefs.getString(KEY_ALARMS, null)),
                alarmsAt = alarmsAt,
                pending = Pending.prune(
                    Pending.fromJson(prefs.getString(KEY_PENDING, null)),
                    todayAt,
                    System.currentTimeMillis(),
                ),
            )
        } catch (e: Exception) {
            UiState()
        }
    }

    override fun onCleared() {
        onStop()
        super.onCleared()
    }

    private companion object {
        const val TAG = "TodoWear"
        const val KEY_TODAY = "today_json"
        const val KEY_TODAY_AT = "today_at"
        const val KEY_ALARMS = "alarms_json"
        const val KEY_ALARMS_AT = "alarms_at"
        const val KEY_PENDING = "pending_json"
    }
}
