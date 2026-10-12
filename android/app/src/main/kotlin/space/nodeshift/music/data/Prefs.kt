package space.nodeshift.music.data

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONObject

object Prefs {
    private lateinit var store: SharedPreferences

    fun init(context: Context) {
        store = context.getSharedPreferences("nsm", Context.MODE_PRIVATE)
    }

    fun string(key: String): String? = store.getString(key, null)

    fun putString(key: String, value: String?) {
        store.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
    }

    fun bool(key: String, default: Boolean): Boolean = store.getBoolean(key, default)

    fun putBool(key: String, value: Boolean) {
        store.edit().putBoolean(key, value).apply()
    }

    fun long(key: String, default: Long = 0): Long = store.getLong(key, default)

    fun putLong(key: String, value: Long) {
        store.edit().putLong(key, value).apply()
    }

    fun doubleMap(key: String): Map<String, Double> {
        val raw = store.getString(key, null) ?: return emptyMap()
        return try {
            val json = JSONObject(raw)
            json.keys().asSequence().associateWith { json.getDouble(it) }
        } catch (_: Exception) {
            emptyMap()
        }
    }

    fun putDoubleMap(key: String, value: Map<String, Double>) {
        val json = JSONObject()
        value.forEach { (name, number) -> json.put(name, number) }
        store.edit().putString(key, json.toString()).apply()
    }
}
