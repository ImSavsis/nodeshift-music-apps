package space.nodeshift.music.site

import android.app.Activity
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeoutOrNull

class SiteSession {
    var user by mutableStateOf<SiteUser?>(null)
        private set
    var isBusy by mutableStateOf(false)
        private set
    var lastError by mutableStateOf<String?>(null)
        private set

    private var pending: CompletableDeferred<Uri?>? = null
    private var tabOpen = false

    var onSessionChanged: (() -> Unit)? = null

    val isLoggedIn: Boolean
        get() = user != null

    suspend fun restore() {
        if (!SiteApi.hasSession) return
        try {
            user = SiteApi.me()
            onSessionChanged?.invoke()
        } catch (error: SiteException) {
            if (error.kind == SiteException.Kind.Unauthorized) user = null
        } catch (_: Exception) {
            lastError = null
        }
    }

    suspend fun login(activity: Activity): Boolean {
        if (isBusy) return false
        isBusy = true
        lastError = null
        try {
            val url = SiteApi.loginUrl()
            val deferred = CompletableDeferred<Uri?>()
            pending = deferred
            tabOpen = true
            CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(activity, Uri.parse(url))
            val callback = withTimeoutOrNull(10 * 60 * 1000L) { deferred.await() }
            tabOpen = false
            pending = null
            if (callback == null) return false
            val token = callback.getQueryParameter("sso_token")
            val state = callback.getQueryParameter("state")
            if (token.isNullOrEmpty() || state.isNullOrEmpty()) throw SiteException(SiteException.Kind.BadCallback)
            val pair = SiteApi.ssoLogin(token, state)
            SiteApi.setTokens(pair.accessToken, pair.refreshToken)
            user = pair.user
            onSessionChanged?.invoke()
            return true
        } catch (error: SiteException) {
            lastError = if (error.kind == SiteException.Kind.BadCallback) {
                "Сайт не вернул данные для входа. Попробуй войти ещё раз."
            } else {
                "Не получилось войти. Проверь интернет и попробуй ещё раз."
            }
            return false
        } catch (_: Exception) {
            lastError = "Не получилось войти. Проверь интернет и попробуй ещё раз."
            return false
        } finally {
            tabOpen = false
            pending = null
            isBusy = false
        }
    }

    fun onCallback(uri: Uri) {
        pending?.complete(uri)
    }

    suspend fun onResumed() {
        val waiting = pending ?: return
        if (!tabOpen) return
        delay(900)
        if (waiting === pending && !waiting.isCompleted) waiting.complete(null)
    }

    fun logout() {
        SiteApi.clear()
        user = null
        onSessionChanged?.invoke()
    }
}
