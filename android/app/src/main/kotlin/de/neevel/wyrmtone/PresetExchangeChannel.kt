package de.neevel.wyrmtone

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Explicit SAF document import/export only. No device, USB or MIDI dependency. */
class PresetExchangeChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "de.neevel.wyrmtone/preset_exchange")
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var payload: ByteArray? = null
    companion object {
        private const val EXPORT = 48041
        private const val IMPORT = 48042
        private const val LIMIT = 3 * 1024 * 1024
    }
    fun start() {
        channel.setMethodCallHandler { call, result ->
            if (pending != null) {
                result.error("PRESET_BUSY", "Eine Dateiauswahl läuft bereits.", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "export" -> runCatching {
                    val text = requireNotNull(call.argument<String>("json"))
                    val bytes = text.toByteArray(Charsets.UTF_8)
                    require(bytes.size <= LIMIT)
                    val name = call.argument<String>("suggestedName")
                        ?.replace(Regex("[^A-Za-z0-9._-]"), "_")?.take(80)
                        ?.takeIf { it.endsWith(".wyrmtone.json") } ?: "preset.wyrmtone.json"
                    pending = result
                    payload = bytes
                    activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/json"
                        putExtra(Intent.EXTRA_TITLE, name)
                    }, EXPORT)
                }.onFailure {
                    pending = null; payload = null
                    result.error("PRESET_EXPORT", "Presetexport konnte nicht gestartet werden.", null)
                }
                "import" -> runCatching {
                    pending = result
                    activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/json"
                    }, IMPORT)
                }.onFailure {
                    pending = null
                    result.error("PRESET_IMPORT", "Presetimport konnte nicht gestartet werden.", null)
                }
                else -> result.notImplemented()
            }
        }
    }
    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != EXPORT && request != IMPORT) return false
        val result = pending
        pending = null
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null) {
            payload = null
            result?.success(if (request == EXPORT) false else null)
            return true
        }
        if (request == EXPORT) {
            val bytes = payload
            payload = null
            executor.execute {
                val success = bytes != null && runCatching {
                    activity.contentResolver.openOutputStream(uri, "w").use {
                        requireNotNull(it).write(bytes)
                    }
                }.isSuccess
                handler.post {
                    if (success) result?.success(true)
                    else result?.error("PRESET_EXPORT", "Preset konnte nicht gespeichert werden.", null)
                }
            }
        } else {
            executor.execute {
                val value = runCatching {
                    activity.contentResolver.openInputStream(uri).use { input ->
                        val stream = requireNotNull(input)
                        val output = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        var total = 0
                        while (true) {
                            val count = stream.read(buffer)
                            if (count < 0) break
                            total += count
                            require(total <= LIMIT)
                            output.write(buffer, 0, count)
                        }
                        output.toString(Charsets.UTF_8.name())
                    }
                }
                handler.post {
                    value.onSuccess { result?.success(it) }
                        .onFailure { result?.error("PRESET_IMPORT", "Presetdatei ist zu groß oder nicht lesbar.", null) }
                }
            }
        }
        return true
    }
    fun dispose() {
        channel.setMethodCallHandler(null)
        pending?.success(null)
        pending = null
        payload = null
        executor.shutdown()
    }
}
