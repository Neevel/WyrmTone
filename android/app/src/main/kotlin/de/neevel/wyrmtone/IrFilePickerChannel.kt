package de.neevel.wyrmtone

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque
import java.io.File

/** Grants persistent, read-only access to a user-selected IR folder. */
class IrFilePickerChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        private const val REQUEST_WAV_FOLDER = 47031
        private const val REQUEST_EXPORT_WAV = 47032
        private const val REQUEST_NAM_FILE = 47033
        private const val PREFERENCES = "ir_saf_preferences"
        private const val TREE_URI_KEY = "ir_tree_uri"
        private const val MAX_DOCUMENTS = 10_000
    }

    private val channel = MethodChannel(messenger, "de.neevel.wyrmtone/ir_files")
    private var pendingResult: MethodChannel.Result? = null
    private var pendingExportFile: File? = null

    fun start() = channel.setMethodCallHandler(this)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickWavFolder" -> pickFolder(result)
            "restorePersistedWavFolder" -> restoreFolder(result)
            "openLocalIr" -> openLocalIr(call, result)
            "exportLocalIr" -> exportLocalIr(call, result)
            "pickNamFile" -> pickNamFile(result)
            else -> result.notImplemented()
        }
    }

    private fun pickNamFile(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("PICK_IN_PROGRESS", "Eine Dateiauswahl ist bereits geöffnet.", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/octet-stream", "application/json", "text/plain", "*/*"))
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, REQUEST_NAM_FILE)
    }

    private fun openLocalIr(call: MethodCall, result: MethodChannel.Result) {
        try {
            val file = validatedLocalIr(call.argument<String>("uri"))
            val contentUri = FileProvider.getUriForFile(
                activity,
                "${activity.packageName}.fileprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(contentUri, "audio/wav")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(Intent.createChooser(intent, "IR-Datei öffnen"))
            result.success(null)
        } catch (error: RuntimeException) {
            result.error("LOCAL_IR_OPEN_FAILED", "Die IR-Datei konnte nicht geöffnet werden.", null)
        }
    }

    private fun exportLocalIr(call: MethodCall, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("PICK_IN_PROGRESS", "Eine Dateiauswahl ist bereits geöffnet.", null)
            return
        }
        try {
            val file = validatedLocalIr(call.argument<String>("uri"))
            val suggestedName = call.argument<String>("fileName")
                ?.replace(Regex("[\\\\/:*?\"<>|]"), "_")
                ?.takeIf { it.endsWith(".wav", ignoreCase = true) }
                ?: "tone3000_ir.wav"
            pendingResult = result
            pendingExportFile = file
            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "audio/wav"
                putExtra(Intent.EXTRA_TITLE, suggestedName)
            }
            activity.startActivityForResult(intent, REQUEST_EXPORT_WAV)
        } catch (error: RuntimeException) {
            result.error("LOCAL_IR_EXPORT_FAILED", "Die IR-Datei konnte nicht exportiert werden.", null)
        }
    }

    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("PICK_IN_PROGRESS", "Eine Ordnerauswahl ist bereits geöffnet.", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, REQUEST_WAV_FOLDER)
    }

    private fun restoreFolder(result: MethodChannel.Result) {
        val encoded = preferences().getString(TREE_URI_KEY, null)
        if (encoded == null) {
            result.success(null)
            return
        }
        val treeUri = Uri.parse(encoded)
        val stillGranted = activity.contentResolver.persistedUriPermissions.any {
            it.uri == treeUri && it.isReadPermission
        }
        if (!stillGranted) {
            preferences().edit().remove(TREE_URI_KEY).apply()
            result.success(null)
            return
        }
        sendFolderResult(treeUri, result)
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == REQUEST_NAM_FILE) {
            val result = pendingResult
            pendingResult = null
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                result?.success(null)
                return true
            }
            try {
                val name = queryDisplayName(uri) ?: "import.nam"
                require(name.endsWith(".nam", ignoreCase = true))
                val bytes = activity.contentResolver.openInputStream(uri).use { input ->
                    requireNotNull(input)
                    input.readBytes()
                }
                require(bytes.size <= 100 * 1024 * 1024)
                result?.success(mapOf("fileName" to name, "uri" to uri.toString(), "bytes" to bytes))
            } catch (error: Exception) {
                result?.error("NAM_IMPORT_FAILED", "Die NAM-Datei konnte nicht gelesen werden.", null)
            }
            return true
        }
        if (requestCode == REQUEST_EXPORT_WAV) {
            val result = pendingResult
            val source = pendingExportFile
            pendingResult = null
            pendingExportFile = null
            val destination = data?.data
            if (resultCode != Activity.RESULT_OK || destination == null || source == null) {
                result?.success(false)
                return true
            }
            try {
                activity.contentResolver.openOutputStream(destination, "w").use { output ->
                    requireNotNull(output)
                    source.inputStream().use { input -> input.copyTo(output) }
                }
                result?.success(true)
            } catch (error: Exception) {
                result?.error(
                    "LOCAL_IR_EXPORT_FAILED",
                    "Die IR-Datei konnte nicht in den ausgewählten Ordner geschrieben werden.",
                    null,
                )
            }
            return true
        }
        if (requestCode != REQUEST_WAV_FOLDER) return false
        val result = pendingResult
        pendingResult = null
        val treeUri = data?.data
        if (resultCode != Activity.RESULT_OK || treeUri == null) {
            result?.success(null)
            return true
        }
        try {
            activity.contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
            preferences().edit().putString(TREE_URI_KEY, treeUri.toString()).apply()
            if (result != null) sendFolderResult(treeUri, result)
        } catch (error: RuntimeException) {
            result?.error(
                "FOLDER_READ_FAILED",
                "Der ausgewählte Ordner konnte nicht dauerhaft lesbar geöffnet werden.",
                error.message,
            )
        }
        return true
    }

    private fun sendFolderResult(treeUri: Uri, result: MethodChannel.Result) {
        try {
            result.success(
                mapOf(
                    "treeUri" to treeUri.toString(),
                    "files" to listWavDocuments(treeUri),
                ),
            )
        } catch (error: RuntimeException) {
            result.error(
                "FOLDER_READ_FAILED",
                "Der gespeicherte IR-Ordner konnte nicht gelesen werden.",
                error.message,
            )
        }
    }

    private fun listWavDocuments(treeUri: Uri): List<Map<String, String>> {
        val resolver = activity.contentResolver
        val rootId = DocumentsContract.getTreeDocumentId(treeUri)
        val pendingIds = ArrayDeque<String>().apply { add(rootId) }
        val visited = mutableSetOf<String>()
        val files = mutableListOf<Map<String, String>>()
        var inspected = 0
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )

        while (pendingIds.isNotEmpty() && inspected < MAX_DOCUMENTS) {
            val parentId = pendingIds.removeFirst()
            if (!visited.add(parentId)) continue
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                treeUri,
                parentId,
            )
            resolver.query(childrenUri, columns, null, null, null)?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(columns[0])
                val nameColumn = cursor.getColumnIndexOrThrow(columns[1])
                val mimeColumn = cursor.getColumnIndexOrThrow(columns[2])
                while (cursor.moveToNext() && inspected < MAX_DOCUMENTS) {
                    inspected++
                    val documentId = cursor.getString(idColumn)
                    val displayName = cursor.getString(nameColumn) ?: continue
                    val mimeType = cursor.getString(mimeColumn)
                    if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
                        pendingIds.add(documentId)
                    } else if (displayName.endsWith(".wav", ignoreCase = true)) {
                        val documentUri = DocumentsContract.buildDocumentUriUsingTree(
                            treeUri,
                            documentId,
                        )
                        files += mapOf(
                            "fileName" to displayName,
                            "uri" to documentUri.toString(),
                        )
                    }
                }
            }
        }
        return files.sortedBy { it["fileName"]?.lowercase() }
    }

    private fun preferences() = activity.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    private fun queryDisplayName(uri: Uri): String? {
        val column = android.provider.OpenableColumns.DISPLAY_NAME
        return activity.contentResolver.query(uri, arrayOf(column), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(cursor.getColumnIndexOrThrow(column)) else null
        }
    }

    private fun validatedLocalIr(encodedUri: String?): File {
        val uri = encodedUri?.let(Uri::parse)
        require(uri?.scheme == "file")
        val allowedDirectory = File(
            activity.applicationInfo.dataDir,
            "app_flutter/tone3000_irs",
        ).canonicalFile
        val file = File(requireNotNull(uri.path)).canonicalFile
        require(file.isFile)
        require(file.path.startsWith(allowedDirectory.path + File.separator))
        return file
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pendingResult = null
        pendingExportFile = null
    }
}
