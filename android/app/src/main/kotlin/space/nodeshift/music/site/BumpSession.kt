package space.nodeshift.music.site

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import org.json.JSONObject
import space.nodeshift.music.data.Prefs
import space.nodeshift.music.net.Net
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.sqrt

enum class BumpPhase { Idle, Listening, Matching, Joining, Failed }

class BumpSession(private val context: Context, private val scope: CoroutineScope) : SensorEventListener {
    var phase by mutableStateOf(BumpPhase.Idle)
        private set
    var text by mutableStateOf("")
        private set
    var sensorAvailable by mutableStateOf(true)
        private set

    private val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var offsetMs = 0.0
    private var deadline = 0L
    private var busy = false
    private var lastBump = 0L
    private var site: SiteSession? = null
    private var onCode: ((String) -> Unit)? = null

    private fun deviceId(): String {
        Prefs.string("nsm_device_id")?.let { return it }
        val fresh = UUID.randomUUID().toString().lowercase()
        Prefs.putString("nsm_device_id", fresh)
        return fresh
    }

    fun start(session: SiteSession, callback: (String) -> Unit) {
        site = session
        onCode = callback
        deadline = System.currentTimeMillis() + 90_000
        phase = BumpPhase.Listening
        text = ""
        val sensor = manager.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)
        sensorAvailable = sensor != null
        if (sensor != null) manager.registerListener(this, sensor, SensorManager.SENSOR_DELAY_GAME)
        scope.launch { syncClock() }
    }

    fun stop() {
        manager.unregisterListener(this)
        onCode = null
        phase = BumpPhase.Idle
        busy = false
    }

    fun triggerManually() {
        scope.launch { submit(System.currentTimeMillis()) }
    }

    override fun onSensorChanged(event: SensorEvent) {
        val magnitude = sqrt(event.values[0] * event.values[0] + event.values[1] * event.values[1] + event.values[2] * event.values[2])
        if (magnitude < 24f) return
        val age = (SystemClock.elapsedRealtimeNanos() - event.timestamp) / 1_000_000
        val moment = System.currentTimeMillis() - age
        if (moment - lastBump < 1200) return
        lastBump = moment
        scope.launch { submit(moment) }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private suspend fun syncClock() {
        var best = Double.MAX_VALUE
        repeat(4) {
            try {
                val sent = System.currentTimeMillis().toDouble()
                val raw = Net.text("${SiteApi.BUMP}/time")
                val received = System.currentTimeMillis().toDouble()
                val server = JSONObject(raw).getDouble("now")
                val rtt = received - sent
                if (rtt < best) {
                    best = rtt
                    offsetMs = server - (sent + received) / 2
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
            }
        }
    }

    private suspend fun submit(impact: Long) {
        if (phase != BumpPhase.Listening || busy || System.currentTimeMillis() > deadline) return
        busy = true
        phase = BumpPhase.Matching
        try {
            val user = site?.user
            val body = JSONObject()
                .put("device", deviceId())
                .put("impact_ms", impact.toDouble())
                .put("offset_ms", offsetMs)
                .put("name", user?.username ?: user?.handle ?: Build.MODEL)
                .put("platform", "android")
                .put("can_host", site?.isLoggedIn == true)
            val result = try {
                Net.execute(Net.postJson("${SiteApi.BUMP}/bump", body.toString())).use { response ->
                    if (!response.isSuccessful) null else JSONObject(response.body.string())
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                null
            }
            if (result == null || !result.optBoolean("matched", false)) {
                phase = BumpPhase.Listening
                return
            }
            if (result.optString("error") == "login_required") {
                manager.unregisterListener(this)
                text = "Войди через сайт хотя бы на одном из телефонов"
                phase = BumpPhase.Failed
                return
            }
            val pair = result.optString("pair")
            val role = result.optString("role")
            if (pair.isEmpty() || role.isEmpty()) {
                phase = BumpPhase.Listening
                return
            }
            manager.unregisterListener(this)
            text = result.optJSONObject("peer")?.optString("name").orEmpty()
            phase = BumpPhase.Joining
            if (role == "host") host(pair) else guest(pair)
        } finally {
            busy = false
        }
    }

    private suspend fun host(pair: String) {
        try {
            val code = SiteApi.createRoom()
            val body = JSONObject().put("device", deviceId()).put("code", code)
            Net.execute(Net.postJson("${SiteApi.BUMP}/pair/$pair/room", body.toString())).close()
            finish(code)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            text = "Не получилось создать комнату"
            phase = BumpPhase.Failed
        }
    }

    private suspend fun guest(pair: String) {
        try {
            val link = "${SiteApi.BUMP}/pair/$pair/room?device=${deviceId()}&wait=15"
            val code = Net.execute(Net.request(link).build()).use { response ->
                if (response.code != 200) null else JSONObject(response.body.string()).optString("code")
            }
            if (code.isNullOrEmpty()) {
                text = "Второй телефон не создал комнату"
                phase = BumpPhase.Failed
                return
            }
            finish(code)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            text = "Не получилось присоединиться"
            phase = BumpPhase.Failed
        }
    }

    private fun finish(code: String) {
        val handler = onCode
        stop()
        handler?.invoke(code)
    }
}
