package space.nodeshift.music

import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.core.content.IntentCompat
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch
import space.nodeshift.music.imports.ImportSource
import space.nodeshift.music.ui.NsmRoot

class MainActivity : ComponentActivity() {
    private val graph: AppGraph
        get() = (application as NsmApp).graph

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        setContent {
            CompositionLocalProvider(LocalGraph provides graph) {
                NsmRoot(this)
            }
        }
        handle(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handle(intent)
    }

    override fun onResume() {
        super.onResume()
        lifecycleScope.launch { graph.site.onResumed() }
    }

    private fun handle(incoming: Intent?) {
        val intent = incoming ?: return
        val data = intent.data
        if (intent.action == Intent.ACTION_VIEW && data != null && data.scheme == "nodeshiftmusic") {
            graph.site.onCallback(data)
            return
        }
        val uris = ArrayList<Uri>()
        when (intent.action) {
            Intent.ACTION_VIEW -> data?.let { uris.add(it) }
            Intent.ACTION_SEND -> IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)?.let { uris.add(it) }
            Intent.ACTION_SEND_MULTIPLE ->
                IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)?.let { uris.addAll(it) }
        }
        if (uris.isNotEmpty()) {
            graph.importer.add(uris.map { ImportSource(it) })
            graph.toasts.show("Добавляем в библиотеку")
        }
    }
}
