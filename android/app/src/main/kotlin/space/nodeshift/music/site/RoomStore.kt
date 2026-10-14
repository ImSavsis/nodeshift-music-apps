package space.nodeshift.music.site

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import space.nodeshift.music.data.Prefs
import space.nodeshift.music.data.TrackRecord
import space.nodeshift.music.net.Net
import space.nodeshift.music.player.PlayerStore
import space.nodeshift.music.player.RepeatMode
import space.nodeshift.music.ui.ToastCenter
import java.util.concurrent.TimeUnit
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

class RoomMember(val id: String, val name: String)

enum class RoomStatus { Idle, Connecting, Live, Reconnecting }

private class RoomState(
    val index: Int,
    val trackId: String?,
    val playing: Boolean,
    val position: Double,
    val stamp: Double,
    val repeat: String,
    val shuffle: Boolean,
    val by: String?,
)

private data class Snap(
    val siteId: String?,
    val queue: List<String>,
    val index: Int,
    val playing: Boolean,
    val seekToken: Int,
    val shuffle: Boolean,
    val repeat: RepeatMode,
)

class RoomStore(
    private val player: PlayerStore,
    private val catalog: CatalogStore,
    private val toasts: ToastCenter,
    private val scope: CoroutineScope,
) {
    var code by mutableStateOf<String?>(null)
        private set
    var status by mutableStateOf(RoomStatus.Idle)
        private set
    var members by mutableStateOf<List<RoomMember>>(emptyList())
        private set
    var you by mutableStateOf<String?>(null)
        private set
    var notice by mutableStateOf<String?>(null)

    private val client: OkHttpClient = Net.client.newBuilder()
        .readTimeout(0, TimeUnit.SECONDS)
        .callTimeout(0, TimeUnit.SECONDS)
        .pingInterval(20, TimeUnit.SECONDS)
        .build()

    private var socket: WebSocket? = null
    private var closedByUser = true
    private var retries = 0
    private var guestName = ""
    private var clockOffset = 0.0
    private var bestRtt = Double.MAX_VALUE
    private var roomQueue: List<SiteTrack> = emptyList()
    private var lastState: RoomState? = null
    private var applyToken = 0
    private var awaitingFirstState = false
    private var suppressUntil = 0L
    private var previous: Snap? = null
    private var timers: Job? = null
    private var watch: Job? = null
    private var reconnect: Job? = null

    val isLive: Boolean
        get() = status == RoomStatus.Live && socket != null

    val link: String?
        get() = code?.let { SiteApi.roomLink(it) }

    fun savedName(): String = Prefs.string("nsm_guest_name") ?: ""

    fun saveName(name: String) {
        Prefs.putString("nsm_guest_name", name)
    }

    fun normalize(raw: String): String? {
        val trimmed = raw.trim()
        val fromLink = Regex("/room/([A-Za-z0-9]+)").find(trimmed)?.groupValues?.get(1)
        val upper = (fromLink ?: trimmed).uppercase()
        val allowed = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        if (upper.length !in 4..8 || upper.any { it !in allowed }) return null
        return upper
    }

    suspend fun create() {
        notice = null
        try {
            join(SiteApi.createRoom(), null)
        } catch (error: CancellationException) {
            throw error
        } catch (error: SiteException) {
            notice = if (error.kind == SiteException.Kind.Unauthorized || error.kind == SiteException.Kind.NoToken) {
                "Войди через сайт, чтобы создать комнату"
            } else {
                "Не получилось создать комнату"
            }
        } catch (_: Exception) {
            notice = "Не получилось создать комнату"
        }
    }

    suspend fun joinChecked(raw: String, name: String?): Boolean {
        notice = null
        val wanted = normalize(raw)
        if (wanted == null) {
            notice = "Код комнаты: 6 символов, буквы и цифры"
            return false
        }
        try {
            if (!SiteApi.roomExists(wanted)) {
                notice = "Такой комнаты нет или она закрыта"
                return false
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            notice = "Не получилось связаться с сервером"
            return false
        }
        join(wanted, name)
        return true
    }

    fun join(wanted: String, name: String?) {
        if (code != null) leave()
        closedByUser = false
        retries = 0
        notice = null
        guestName = (name ?: savedName()).trim()
        roomQueue = emptyList()
        lastState = null
        members = emptyList()
        you = null
        code = wanted
        status = RoomStatus.Connecting
        previous = snapshot()
        startWatch()
        connect(wanted)
    }

    fun leave() {
        closedByUser = true
        timers?.cancel()
        watch?.cancel()
        reconnect?.cancel()
        applyToken += 1
        val current = socket
        socket = null
        current?.close(1000, null)
        roomQueue = emptyList()
        lastState = null
        previous = null
        code = null
        members = emptyList()
        you = null
        status = RoomStatus.Idle
    }

    private fun serverNow(): Double = System.currentTimeMillis() + clockOffset

    private fun expected(state: RoomState): Double =
        if (state.playing) state.position + (serverNow() - state.stamp) / 1000 else state.position

    private fun connect(wanted: String) {
        scope.launch {
            val token = SiteApi.freshAccessToken()
            if (closedByUser || code != wanted) return@launch
            bestRtt = Double.MAX_VALUE
            val request = Request.Builder().url(SiteApi.roomSocketUrl(wanted)).build()
            val created = client.newWebSocket(request, object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    val hello = JSONObject().put("type", "hello").put("name", guestName)
                    if (token != null) hello.put("token", token)
                    webSocket.send(hello.toString())
                    scope.launch { startTimers() }
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    scope.launch { handle(text) }
                }

                override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                    scope.launch { closed(webSocket, wanted) }
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    scope.launch { closed(webSocket, wanted) }
                }
            })
            socket = created
        }
    }

    private fun closed(webSocket: WebSocket, wanted: String) {
        if (socket !== webSocket) return
        timers?.cancel()
        socket = null
        if (closedByUser) return
        if (retries >= 12) {
            toasts.show("Связь с комнатой потеряна")
            leave()
            return
        }
        retries += 1
        status = RoomStatus.Reconnecting
        reconnect = scope.launch {
            delay(min(retries, 8) * 1000L)
            if (!closedByUser && code == wanted) connect(wanted)
        }
    }

    private fun post(message: JSONObject) {
        socket?.send(message.toString())
    }

    private fun handle(raw: String) {
        val json = try {
            JSONObject(raw)
        } catch (_: Exception) {
            return
        }
        when (json.optString("type")) {
            "welcome" -> {
                retries = 0
                awaitingFirstState = true
                status = RoomStatus.Live
                you = json.optString("you")
            }
            "members" -> members = parseMembers(json.optJSONArray("members"))
            "queue" -> roomQueue = decodeTracks(json.optJSONArray("tracks"))
            "state" -> handleState(json)
            "pong" -> handlePong(json)
            "error" -> {
                toasts.show(if (json.optString("reason") == "full") "В комнате нет мест" else "Комната закрыта или не найдена")
                leave()
            }
        }
    }

    private fun handlePong(json: JSONObject) {
        val sent = json.optDouble("t", Double.NaN)
        val server = json.optDouble("server", Double.NaN)
        if (sent.isNaN() || server.isNaN()) return
        val now = System.currentTimeMillis().toDouble()
        val rtt = now - sent
        if (rtt <= bestRtt + 30) {
            bestRtt = min(bestRtt, rtt)
            clockOffset = server - (sent + now) / 2
        }
    }

    private fun handleState(json: JSONObject) {
        val state = RoomState(
            index = json.optInt("index", -1),
            trackId = if (json.isNull("track_id")) null else json.opt("track_id").toString(),
            playing = json.optBoolean("playing", false),
            position = json.optDouble("position", 0.0),
            stamp = json.optDouble("stamp", 0.0),
            repeat = json.optString("repeat", "off"),
            shuffle = json.optBoolean("shuffle", false),
            by = if (json.isNull("by")) null else json.optString("by"),
        )
        if (awaitingFirstState) {
            awaitingFirstState = false
            if (state.trackId == null && player.current?.siteId != null) {
                lastState = state
                sendQueue(false)
                return
            }
        }
        if (state.by != null && state.by == you) {
            lastState = state
            return
        }
        apply(state)
    }

    private fun apply(state: RoomState) {
        lastState = state
        if (state.index !in roomQueue.indices) return
        applyToken += 1
        val token = applyToken
        val records = roomQueue.map { catalog.record(it) }
        val target = records[state.index]
        suppressUntil = System.currentTimeMillis() + 2500
        if (player.current?.siteId != target.siteId) {
            player.play(target, records)
        }
        if (player.isPlaying != state.playing) {
            if (state.playing) player.resume() else player.pause()
        }
        if (player.shuffle != state.shuffle) player.applyShuffle(state.shuffle)
        var guard = 0
        while (player.repeatMode.name.lowercase() != wireRepeat(state.repeat) && guard < 3) {
            player.cycleRepeat()
            guard += 1
        }
        scope.launch { syncPosition(state, token) }
    }

    private fun wireRepeat(value: String): String = when (value) {
        "all" -> "all"
        "one" -> "one"
        else -> "off"
    }

    private suspend fun syncPosition(state: RoomState, token: Int) {
        var waited = 0
        while (token == applyToken && player.duration <= 0.0 && waited < 20_000) {
            delay(150)
            waited += 150
        }
        if (token != applyToken) return
        delay(250)
        val target = expected(state)
        suppressUntil = System.currentTimeMillis() + 1500
        if (abs(player.time() - target) > 0.35) player.seek(max(0.0, target))
        if (state.playing && !player.isPlaying) player.resume()
    }

    private fun startTimers() {
        timers?.cancel()
        timers = scope.launch {
            launch {
                repeat(4) {
                    delay(if (it == 0) 300 else 400)
                    ping()
                }
                while (true) {
                    delay(5000)
                    ping()
                }
            }
            while (true) {
                delay(2000)
                correctDrift()
            }
        }
    }

    private fun ping() {
        post(JSONObject().put("type", "ping").put("t", System.currentTimeMillis().toDouble()))
    }

    private fun correctDrift() {
        val state = lastState ?: return
        if (!state.playing || !player.isPlaying || player.duration <= 0.0) return
        if (player.current?.siteId != state.trackId) return
        val target = expected(state)
        if (abs(player.time() - target) > 0.7) {
            suppressUntil = System.currentTimeMillis() + 1500
            player.seek(max(0.0, target))
        }
    }

    private fun snapshot(): Snap = Snap(
        siteId = player.current?.siteId,
        queue = player.queueIds,
        index = player.currentIndex,
        playing = player.isPlaying,
        seekToken = player.seekToken,
        shuffle = player.shuffle,
        repeat = player.repeatMode,
    )

    private fun startWatch() {
        watch?.cancel()
        watch = scope.launch {
            snapshotFlow { snapshot() }.collect { changed(it) }
        }
    }

    private fun sharedQueue(): Pair<List<Long>, Int>? {
        val ids = ArrayList<Long>()
        var mapped = -1
        player.queue.forEachIndexed { position, track ->
            val number = track.siteId?.toLongOrNull() ?: return@forEachIndexed
            ids.add(number)
            if (position == player.currentIndex) mapped = ids.size - 1
        }
        return if (mapped >= 0) ids to mapped else null
    }

    private fun sendQueue(keep: Boolean) {
        val shared = sharedQueue() ?: return
        post(
            JSONObject()
                .put("type", "set_queue")
                .put("ids", JSONArray(shared.first))
                .put("index", shared.second)
                .put("keep", keep)
                .put("position", player.time())
                .put("playing", player.isPlaying),
        )
    }

    private fun changed(now: Snap) {
        val before = previous
        previous = now
        if (status != RoomStatus.Live || before == null || before == now) return
        if (System.currentTimeMillis() < suppressUntil) return
        if (now.siteId != before.siteId && player.current != null) {
            if (now.siteId == null) {
                toasts.show("Этот трек есть только на телефоне, в комнату его не отправить")
                return
            }
            val shared = sharedQueue()
            val ids = roomQueue.map { it.id.value }
            if (shared != null && shared.first.map { it.toString() } == ids) {
                post(JSONObject().put("type", "jump").put("index", shared.second))
            } else {
                sendQueue(false)
            }
            return
        }
        if (now.queue != before.queue && player.current != null) sendQueue(true)
        if (now.playing != before.playing && player.current != null) {
            post(JSONObject().put("type", if (now.playing) "play" else "pause").put("position", player.time()))
        }
        if (now.seekToken != before.seekToken) {
            post(JSONObject().put("type", "seek").put("position", player.time()))
        }
        if (now.repeat != before.repeat) post(JSONObject().put("type", "repeat").put("mode", now.repeat.name.lowercase()))
        if (now.shuffle != before.shuffle) post(JSONObject().put("type", "shuffle").put("on", now.shuffle))
    }

    private fun parseMembers(array: JSONArray?): List<RoomMember> {
        if (array == null) return emptyList()
        return (0 until array.length()).mapNotNull { index ->
            val item = array.optJSONObject(index) ?: return@mapNotNull null
            RoomMember(item.optString("id"), item.optString("name", "Слушатель"))
        }
    }

    private fun decodeTracks(array: JSONArray?): List<SiteTrack> {
        if (array == null) return emptyList()
        return (0 until array.length()).mapNotNull { index ->
            val item = array.optJSONObject(index) ?: return@mapNotNull null
            try {
                Net.snakeJson.decodeFromString<SiteTrack>(item.toString())
            } catch (_: Exception) {
                null
            }
        }
    }
}
