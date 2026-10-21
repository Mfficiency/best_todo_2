package com.mfficiency.best_todo_2.wear

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.ScalingLazyListScope
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.Colors
import androidx.wear.compose.material.CompactChip
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.ListHeader
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.Vignette
import androidx.wear.compose.material.VignettePosition
import androidx.wear.compose.navigation.SwipeDismissableNavHost
import androidx.wear.compose.navigation.composable
import androidx.wear.compose.navigation.rememberSwipeDismissableNavController
import com.mfficiency.best_todo_2.wear.core.AlarmRow
import com.mfficiency.best_todo_2.wear.core.Connection
import com.mfficiency.best_todo_2.wear.core.Labels
import com.mfficiency.best_todo_2.wear.core.Pending
import com.mfficiency.best_todo_2.wear.core.TaskRow
import java.time.ZoneId
import kotlinx.coroutines.delay

// The phone app's seed blue (lib/main.dart _seedColor 0xFF005FDD), lifted
// for a black watch face.
private val TodoColors = Colors(
    primary = Color(0xFF8AB4FF),
    primaryVariant = Color(0xFF005FDD),
    secondary = Color(0xFF8AB4FF),
    secondaryVariant = Color(0xFF005FDD),
    background = Color.Black,
    onPrimary = Color(0xFF00205A),
    onSecondary = Color(0xFF00205A),
)

/** How long a first tap waits for the confirming second one. */
private const val CONFIRM_MS = 4_000L

@Composable
fun TodoWearApp(viewModel: TodoViewModel) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    MaterialTheme(colors = TodoColors) {
        val nav = rememberSwipeDismissableNavController()
        SwipeDismissableNavHost(navController = nav, startDestination = "main") {
            composable("main") {
                MainScreen(
                    state = state,
                    onComplete = viewModel::complete,
                    onRefresh = viewModel::refresh,
                    onAlarms = { nav.navigate("alarms") },
                )
            }
            composable("alarms") {
                AlarmsScreen(state = state, onRefresh = viewModel::refresh)
            }
        }
    }
}

@Composable
private fun ListScreen(content: ScalingLazyListScope.() -> Unit) {
    val listState = rememberScalingLazyListState()
    Scaffold(
        timeText = { TimeText() },
        vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        // Scrolls with the rotating bezel by itself (Wear Compose 1.4).
        ScalingLazyColumn(
            modifier = Modifier.fillMaxSize(),
            state = listState,
            horizontalAlignment = Alignment.CenterHorizontally,
            content = content,
        )
    }
}

@Composable
private fun MainScreen(
    state: UiState,
    onComplete: (String) -> Unit,
    onRefresh: () -> Unit,
    onAlarms: () -> Unit,
) {
    // First tap arms a row, a second tap within CONFIRM_MS completes it (no
    // undo on the watch, so a brush of the screen must not finish a task).
    var armed by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(armed) {
        if (armed != null) {
            delay(CONFIRM_MS)
            armed = null
        }
    }
    val onTap: (TaskRow) -> Unit = { row ->
        if (!row.done) {
            if (armed == row.id) {
                armed = null
                onComplete(row.id)
            } else {
                armed = row.id
            }
        }
    }
    val now = System.currentTimeMillis()
    val zone = ZoneId.systemDefault()
    val pendingIds = state.pending.map { it.id }.toSet()
    val deliveredIds = state.pending.filter { it.delivered }.map { it.id }.toSet()

    ListScreen {
        item { StatusLine(state) }
        val today = state.today
        if (today == null) {
            item { Note(stringResource(R.string.no_data)) }
        } else {
            item {
                val header = if (Labels.isStaleDay(today.day, now, zone) && state.todayAt != null) {
                    stringResource(
                        R.string.header_today_stale,
                        Labels.savedAt(state.todayAt, now, zone),
                    )
                } else {
                    stringResource(R.string.header_today)
                }
                ListHeader { Text(header) }
            }
            val rows = Pending.applyTo(today.today, state.pending)
            if (rows.isEmpty() || rows.all { it.done }) {
                item { Note(stringResource(R.string.nothing_today)) }
            }
            items(rows, key = { "today-" + it.id }) { row ->
                TaskChip(row, armed == row.id, row.id in pendingIds, row.id in deliveredIds) { onTap(row) }
            }
            if (today.todayMore > 0) {
                item { Note(stringResource(R.string.more_on_phone, today.todayMore)) }
            }
        }
        item { AlarmsChip(state, now, zone, onAlarms) }
        if (today != null) {
            item { ListHeader { Text(stringResource(R.string.header_tomorrow)) } }
            val rows = Pending.applyTo(today.tomorrow, state.pending)
            if (rows.isEmpty()) {
                item { Note(stringResource(R.string.nothing_tomorrow)) }
            }
            items(rows, key = { "tomorrow-" + it.id }) { row ->
                TaskChip(row, armed == row.id, row.id in pendingIds, row.id in deliveredIds) { onTap(row) }
            }
            if (today.tomorrowMore > 0) {
                item { Note(stringResource(R.string.more_on_phone, today.tomorrowMore)) }
            }
        }
        item { RefreshChip(state.loading, onRefresh) }
    }
}

@Composable
private fun AlarmsScreen(state: UiState, onRefresh: () -> Unit) {
    val now = System.currentTimeMillis()
    val zone = ZoneId.systemDefault()
    ListScreen {
        item { ListHeader { Text(stringResource(R.string.header_alarms)) } }
        val alarms = state.alarms
        if (alarms == null) {
            item { Note(stringResource(R.string.no_data)) }
        } else if (alarms.isEmpty()) {
            item { Note(stringResource(R.string.no_alarms)) }
        } else {
            items(alarms, key = { "alarm-" + it.id }) { alarm -> AlarmCard(alarm, now, zone) }
        }
        item { RefreshChip(state.loading, onRefresh) }
    }
}

@Composable
private fun StatusLine(state: UiState) {
    val now = System.currentTimeMillis()
    val saved = state.todayAt?.let { Labels.savedAt(it, now, ZoneId.systemDefault()) }
    val text = when (state.connection) {
        Connection.CHECKING ->
            if (saved != null) stringResource(R.string.status_saved, saved)
            else stringResource(R.string.status_connecting)
        Connection.CONNECTED -> stringResource(R.string.status_connected)
        Connection.NO_APP -> stringResource(R.string.status_no_app)
        Connection.UNREACHABLE ->
            if (saved != null) stringResource(R.string.status_unreachable_saved, saved)
            else stringResource(R.string.status_unreachable)
    }
    val color = when (state.connection) {
        Connection.CONNECTED -> MaterialTheme.colors.primary
        Connection.CHECKING -> MaterialTheme.colors.onSurfaceVariant
        else -> Color(0xFFFFB74D)
    }
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = text,
            style = MaterialTheme.typography.caption2,
            color = color,
            textAlign = TextAlign.Center,
        )
        val error = state.error
        if (error != null) {
            Text(
                text = stringResource(error),
                style = MaterialTheme.typography.caption3,
                color = MaterialTheme.colors.error,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun TaskChip(
    row: TaskRow,
    armed: Boolean,
    pending: Boolean,
    delivered: Boolean,
    onClick: () -> Unit,
) {
    val secondary: String? = when {
        armed -> stringResource(R.string.tap_again)
        pending && delivered -> stringResource(R.string.sent_to_phone)
        pending -> stringResource(R.string.waiting_for_phone)
        else -> null
    }
    Chip(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        label = {
            Text(
                text = row.title,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                textDecoration = if (row.done) TextDecoration.LineThrough else null,
            )
        },
        secondaryLabel = if (secondary != null) {
            { Text(text = secondary, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        } else {
            null
        },
        icon = {
            if (row.done) {
                Icon(
                    imageVector = Icons.Filled.CheckCircle,
                    contentDescription = null,
                    modifier = Modifier.size(ChipDefaults.IconSize),
                )
            } else {
                Box(
                    modifier = Modifier
                        .size(ChipDefaults.IconSize)
                        .border(2.dp, MaterialTheme.colors.primary, CircleShape),
                )
            }
        },
        colors = when {
            armed -> ChipDefaults.primaryChipColors()
            row.done -> ChipDefaults.childChipColors()
            else -> ChipDefaults.secondaryChipColors()
        },
    )
}

@Composable
private fun AlarmsChip(state: UiState, now: Long, zone: ZoneId, onClick: () -> Unit) {
    val next = state.alarms?.firstOrNull { it.on && it.next != null }
    val nextText = next?.let {
        Labels.nextRing(
            it.next,
            now,
            zone,
            stringResource(R.string.word_today),
            stringResource(R.string.word_tomorrow),
        )
    }
    Chip(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        label = { Text(stringResource(R.string.alarms_chip)) },
        secondaryLabel = if (nextText != null) {
            { Text(text = stringResource(R.string.alarm_next, nextText), maxLines = 1) }
        } else {
            null
        },
        icon = {
            Icon(
                imageVector = Icons.Filled.Notifications,
                contentDescription = null,
                modifier = Modifier.size(ChipDefaults.IconSize),
            )
        },
        colors = ChipDefaults.secondaryChipColors(),
    )
}

/** One alarm, read-only (alarms are set up on the phone). */
@Composable
private fun AlarmCard(alarm: AlarmRow, now: Long, zone: ZoneId) {
    val dim = MaterialTheme.colors.onSurfaceVariant
    val ring = Labels.nextRing(
        alarm.next,
        now,
        zone,
        stringResource(R.string.word_today),
        stringResource(R.string.word_tomorrow),
    )
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(20.dp))
            .background(MaterialTheme.colors.surface)
            .padding(horizontal = 14.dp, vertical = 8.dp),
    ) {
        Text(
            text = alarm.time,
            style = MaterialTheme.typography.title2,
            color = if (alarm.on) MaterialTheme.colors.onSurface else dim,
        )
        Text(
            text = if (alarm.sub.isBlank()) alarm.name else alarm.name + " · " + alarm.sub,
            style = MaterialTheme.typography.caption2,
            color = dim,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = if (ring != null) stringResource(R.string.alarm_next, ring)
            else stringResource(R.string.alarm_off),
            style = MaterialTheme.typography.caption3,
            color = if (alarm.on) MaterialTheme.colors.primary else dim,
        )
    }
}

@Composable
private fun RefreshChip(loading: Boolean, onClick: () -> Unit) {
    CompactChip(
        onClick = onClick,
        enabled = !loading,
        label = { Text(stringResource(R.string.refresh)) },
        icon = {
            Icon(
                imageVector = Icons.Filled.Refresh,
                contentDescription = null,
                modifier = Modifier.size(ChipDefaults.SmallIconSize),
            )
        },
        colors = ChipDefaults.secondaryChipColors(),
    )
}

@Composable
private fun Note(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.caption2,
        color = MaterialTheme.colors.onSurfaceVariant,
        textAlign = TextAlign.Center,
        modifier = Modifier.padding(horizontal = 8.dp),
    )
}
