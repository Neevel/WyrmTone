package de.neevel.wyrmtone

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import org.json.JSONObject

/** Only explicit JSON export to a user-chosen SAF document, never a MIDI port. */
class MidiCaptureExportChannel(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "de.neevel.wyrmtone/midi_capture_export")
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var payload: ByteArray? = null
    companion object { private const val REQUEST = 47034 }
    fun start() {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "exportJson") { result.notImplemented(); return@setMethodCallHandler }
            if (pending != null) { result.error("EXPORT_BUSY", "Export läuft bereits.", null); return@setMethodCallHandler }
            try {
                val text = requireNotNull(call.argument<String>("json"))
                require(text.length <= 3 * 1024 * 1024)
                val json = JSONObject(text)
                require(json.getJSONObject("session").getBoolean("receiveOnly"))
                payload = text.toByteArray(Charsets.UTF_8)
                pending = result
                activity.startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/json"
                    putExtra(Intent.EXTRA_TITLE, "wyrmtone_midi_capture_${System.currentTimeMillis()}.json")
                }, REQUEST)
            } catch (_: Exception) {
                payload = null; pending = null
                result.error("EXPORT_FAILED", "Diagnoseexport konnte nicht gestartet werden.", null)
            }
        }
    }
    fun onActivityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != REQUEST) return false
        val result = pending; val bytes = payload
        pending = null; payload = null
        val uri = data?.data
        if (code != Activity.RESULT_OK || uri == null || bytes == null) { result?.success(false); return true }
        executor.execute {
            val success = runCatching {
                activity.contentResolver.openOutputStream(uri, "w").use { requireNotNull(it).write(bytes) }
            }.isSuccess
            handler.post {
                if (success) result?.success(true)
                else result?.error("EXPORT_FAILED", "Diagnose konnte nicht gespeichert werden.", null)
            }
        }
        return true
    }
    fun dispose() { channel.setMethodCallHandler(null); pending?.success(false); pending = null; payload = null; executor.shutdown() }
}
