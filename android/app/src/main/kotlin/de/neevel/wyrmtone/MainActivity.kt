package de.neevel.wyrmtone

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var usbChannels: UsbPlatformChannels? = null
    private var irFilePicker: IrFilePickerChannel? = null
    private var tone3000OAuth: Tone3000OAuthChannel? = null
    private var midiExport: MidiCaptureExportChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        usbChannels = UsbPlatformChannels(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.start() }
        irFilePicker = IrFilePickerChannel(this, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.start() }
        tone3000OAuth = Tone3000OAuthChannel(this, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.start(intent) }
        midiExport = MidiCaptureExportChannel(this, flutterEngine.dartExecutor.binaryMessenger)
            .also { it.start() }
    }

    @Deprecated("Legacy callback required by the FlutterActivity integration used here")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (midiExport?.onActivityResult(requestCode, resultCode, data) == true) return
        if (irFilePicker?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        tone3000OAuth?.handleIntent(intent)
    }

    override fun onDestroy() {
        midiExport?.dispose()
        midiExport = null
        usbChannels?.dispose()
        usbChannels = null
        irFilePicker?.dispose()
        irFilePicker = null
        tone3000OAuth?.dispose()
        tone3000OAuth = null
        super.onDestroy()
    }

    override fun onPause() {
        usbChannels?.pause()
        super.onPause()
    }
}
