package de.neevel.wyrmtone

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Opens TONE3000 in the system browser and forwards only the registered callback URI. */
class Tone3000OAuthChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "de.neevel.wyrmtone/tone3000_oauth")
    private var dartReady = false
    private var pendingCallback: String? = null

    fun start(initialIntent: Intent?) {
        channel.setMethodCallHandler(this)
        handleIntent(initialIntent)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "startListening") {
            dartReady = true
            pendingCallback?.let { channel.invokeMethod("oauthCallback", it) }
            pendingCallback = null
            result.success(null)
            return
        }
        if (call.method != "openAuthorization") {
            result.notImplemented()
            return
        }
        val encoded = call.argument<String>("url")
        val uri = encoded?.let(Uri::parse)
        if (uri == null ||
            uri.scheme != "https" ||
            uri.host != "www.tone3000.com" ||
            uri.path != "/api/v1/oauth/authorize"
        ) {
            result.error("INVALID_AUTH_URL", "Nur der offizielle TONE3000-Login ist erlaubt.", null)
            return
        }
        try {
            activity.startActivity(
                Intent(Intent.ACTION_VIEW, uri).apply {
                    addCategory(Intent.CATEGORY_BROWSABLE)
                },
            )
            result.success(null)
        } catch (error: RuntimeException) {
            result.error("BROWSER_FAILED", "Der Systembrowser konnte nicht geöffnet werden.", null)
        }
    }

    fun handleIntent(intent: Intent?): Boolean {
        val uri = intent?.data ?: return false
        if (uri.scheme != "wyrmtone" || uri.host != "oauth" || uri.path != "/callback") {
            return false
        }
        if (dartReady) {
            channel.invokeMethod("oauthCallback", uri.toString())
        } else {
            pendingCallback = uri.toString()
        }
        return true
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        dartReady = false
        pendingCallback = null
    }
}
