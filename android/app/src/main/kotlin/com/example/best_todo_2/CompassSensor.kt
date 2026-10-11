package com.mfficiency.best_todo_2

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

// Streams the phone's heading (degrees clockwise from magnetic north, 0..360)
// to the Compass tool (lib/ui/compass_page.dart). Uses the fused rotation
// vector sensor when present, else accelerometer + magnetometer. Listens only
// while the Dart side is subscribed, so the sensors are off whenever the
// Compass page is closed. Emits an error ("no-sensor") on devices without
// the hardware.
object CompassSensor {
    fun register(context: Context, messenger: BinaryMessenger) {
        val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
        EventChannel(messenger, "besttodo/compass").setStreamHandler(object : EventChannel.StreamHandler {
            private var listener: SensorEventListener? = null

            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                val rotation = manager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
                val accel = manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
                val magnet = manager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
                if (rotation == null && (accel == null || magnet == null)) {
                    events.error("no-sensor", "This device has no compass sensor", null)
                    return
                }
                val matrix = FloatArray(9)
                val orientation = FloatArray(3)
                val gravity = FloatArray(3)
                val geomagnetic = FloatArray(3)
                var hasGravity = false
                var hasGeomagnetic = false
                val l = object : SensorEventListener {
                    override fun onSensorChanged(event: SensorEvent) {
                        when (event.sensor.type) {
                            Sensor.TYPE_ROTATION_VECTOR ->
                                SensorManager.getRotationMatrixFromVector(matrix, event.values)
                            Sensor.TYPE_ACCELEROMETER -> {
                                event.values.copyInto(gravity, 0, 0, 3)
                                hasGravity = true
                                if (!hasGeomagnetic ||
                                    !SensorManager.getRotationMatrix(matrix, null, gravity, geomagnetic)) return
                            }
                            Sensor.TYPE_MAGNETIC_FIELD -> {
                                event.values.copyInto(geomagnetic, 0, 0, 3)
                                hasGeomagnetic = true
                                if (!hasGravity ||
                                    !SensorManager.getRotationMatrix(matrix, null, gravity, geomagnetic)) return
                            }
                            else -> return
                        }
                        SensorManager.getOrientation(matrix, orientation)
                        val degrees = (Math.toDegrees(orientation[0].toDouble()) + 360.0) % 360.0
                        events.success(degrees)
                    }

                    override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}
                }
                listener = l
                if (rotation != null) {
                    manager.registerListener(l, rotation, SensorManager.SENSOR_DELAY_UI)
                } else {
                    manager.registerListener(l, accel, SensorManager.SENSOR_DELAY_UI)
                    manager.registerListener(l, magnet, SensorManager.SENSOR_DELAY_UI)
                }
            }

            override fun onCancel(arguments: Any?) {
                listener?.let { manager.unregisterListener(it) }
                listener = null
            }
        })
    }
}
