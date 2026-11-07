package com.mfficiency.best_todo_2.wear

import android.content.Context
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.Wearable
import com.mfficiency.best_todo_2.wear.core.Paths
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

/** One Data Layer item from the phone: its JSON and when it was published. */
data class Snapshot(val path: String, val json: String, val at: Long)

/**
 * The Wearable Data Layer, as this app uses it (see README.md › Sync):
 * reads the phone's `/todo/…` items, finds the phone by its `todo_phone`
 * capability and sends it `/todo/command/complete`. Every call can throw;
 * the caller ([TodoViewModel]) catches.
 */
class PhoneLink(context: Context) {
    private val app = context.applicationContext
    private val dataClient: DataClient = Wearable.getDataClient(app)
    private val messageClient = Wearable.getMessageClient(app)
    private val capabilityClient = Wearable.getCapabilityClient(app)
    private val nodeClient = Wearable.getNodeClient(app)

    suspend fun readItems(): List<Snapshot> = withTimeout(TIMEOUT_MS) {
        val buffer = dataClient.dataItems.await()
        try {
            val out = ArrayList<Snapshot>()
            for (item in buffer) {
                val snapshot = snapshotOf(item)
                if (snapshot != null) out.add(snapshot)
            }
            out
        } finally {
            buffer.release()
        }
    }

    fun addListener(listener: DataClient.OnDataChangedListener) {
        dataClient.addListener(listener)
    }

    fun removeListener(listener: DataClient.OnDataChangedListener) {
        dataClient.removeListener(listener)
    }

    /** The reachable phone running BestToDo, or null. */
    suspend fun phoneNode(): Node? = withTimeout(TIMEOUT_MS) {
        val info = capabilityClient
            .getCapability(Paths.PHONE_CAPABILITY, CapabilityClient.FILTER_REACHABLE)
            .await()
        val nodes = info.nodes
        nodes.firstOrNull { it.isNearby } ?: nodes.firstOrNull()
    }

    /** Whether any phone is connected at all (with or without BestToDo). */
    suspend fun anyPhoneConnected(): Boolean = withTimeout(TIMEOUT_MS) {
        nodeClient.connectedNodes.await().isNotEmpty()
    }

    suspend fun sendComplete(nodeId: String, taskId: String) {
        withTimeout(TIMEOUT_MS) {
            messageClient
                .sendMessage(nodeId, Paths.COMPLETE, taskId.toByteArray(Charsets.UTF_8))
                .await()
        }
    }

    companion object {
        private const val TIMEOUT_MS = 8_000L

        fun snapshotOf(item: DataItem): Snapshot? {
            val path = item.uri.path ?: return null
            if (path != Paths.TODAY && path != Paths.ALARMS) return null
            val map = DataMapItem.fromDataItem(item).dataMap
            val json = map.getString("json") ?: return null
            return Snapshot(path, json, map.getLong("at"))
        }
    }
}
