package de.neevel.wyrmtone

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

/** Fixed official editor reference: capture 02, OUT 03, frames 779/780. */
object VerifiedGain41Reference {
    private const val HEX = "f021257f514d453212100300020407000000000007000000000000000002040402f7"
    const val SHA256 = "00a5945fc81c6345e37e9662314490e675b5d7080b76c285e09c339f2a2a57ed"
    fun bytes(): ByteArray = HEX.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    internal fun validate(data: ByteArray) {
        require(data.size == 34) { "Referenzlänge falsch." }
        require(data.first() == 0xf0.toByte() && data.last() == 0xf7.toByte()) { "SysEx-Grenzen falsch." }
        require(data.copyOfRange(4, 8).contentEquals("QME2".toByteArray(Charsets.US_ASCII))) { "Header falsch." }
        fun unpack(start: Int, count: Int): ByteArray = ByteArray(count) { i ->
            val high = data[start + 2 * i].toInt()
            val low = data[start + 2 * i + 1].toInt()
            require(high in 0..15 && low in 0..15) { "Nibble ungültig." }
            (high * 16 + low).toByte()
        }
        require(ByteBuffer.wrap(unpack(13, 4)).order(ByteOrder.LITTLE_ENDIAN).int == 0x07000047) { "Algorithmus falsch." }
        require(ByteBuffer.wrap(unpack(21, 2)).order(ByteOrder.LITTLE_ENDIAN).short.toInt() == 0) { "Gain-Index falsch." }
        require(ByteBuffer.wrap(unpack(25, 4)).order(ByteOrder.LITTLE_ENDIAN).float == 41.0f) { "Zielwert falsch." }
        require(data.contentEquals(bytes())) { "Keine bytegleiche Editor-Referenz." }
        val sha = MessageDigest.getInstance("SHA-256").digest(data).joinToString("") { "%02x".format(it) }
        require(sha == SHA256) { "Referenzhash falsch." }
    }
}

internal data class ProbeEligibility(
    val enabled: Boolean, val connection: String?, val vendor: Int?, val product: Int?,
    val uniqueUsb: Boolean, val uniqueMidi: Boolean, val directlyMapped: Boolean,
    val deviceOpen: Boolean, val expectedInput: Boolean, val monitoring: Boolean,
) {
    fun check() {
        require(enabled) { "Compile-Time-Freigabe fehlt." }
        require(connection != null && vendor == 0x84ef && product == 0x0054) { "Falsches oder getrenntes USB-Gerät." }
        require(uniqueUsb && uniqueMidi && directlyMapped) { "Matribox nicht eindeutig direkt USB/MIDI zugeordnet." }
        require(deviceOpen) { "MIDI-Gerät nicht geöffnet." }
        require(expectedInput) { "Erwarteter eindeutiger Input-Port 0 fehlt." }
        require(!monitoring) { "Passiven Monitor zuerst stoppen." }
    }
}

/** The fakeable port cannot accept arbitrary bytes, values or commands. */
internal interface VerifiedProbePort {
    fun sendVerifiedGain41()
    fun close()
}

internal class VerifiedMatriboxProbe(
    private val eligibility: () -> ProbeEligibility,
    private val openPort: () -> VerifiedProbePort,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val inProgress = AtomicBoolean(false)
    private val lock = Any()
    private val attemptedConnections = mutableSetOf<String>()
    private var generation = 0
    private var port: VerifiedProbePort? = null
    private val logs = mutableListOf<String>()
    private fun log(event: String, details: String) {
        logs.add("[${clock()}] $event $details")
        if (logs.size > 100) logs.removeAt(0)
    }
    fun status(): Map<String, Any?> = synchronized(lock) {
        val current = eligibility()
        mapOf("enabled" to current.enabled, "attempted" to (current.connection in attemptedConnections),
            "connection" to current.connection, "busy" to inProgress.get(),
            "ready" to runCatching { current.check() }.isSuccess, "logs" to logs.toList())
    }
    fun sendVerifiedSol100OdGain41Probe(): Map<String, Any?> {
        check(inProgress.compareAndSet(false, true)) { "Sendevorgang läuft bereits. Es wurde kein weiterer Sendeversuch durchgeführt." }
        var calls = 0
        var opened: VerifiedProbePort? = null
        var success = false
        var failure: String? = null
        try {
            val token: Int
            val connection: String
            synchronized(lock) {
                val current = eligibility()
                current.check()
                VerifiedGain41Reference.validate(VerifiedGain41Reference.bytes())
                connection = requireNotNull(current.connection)
                check(connection !in attemptedConnections) { "Test in dieser Verbindung bereits ausgeführt." }
                attemptedConnections.add(connection) // Consume also on port-open/send failure. Never retry.
                token = generation
                log("MANUAL_CONFIRMATION", "Sonicake Matribox 1 84EF:0054 Sol 100 OD Gain-Index 0 Zielwert 41")
            }
            opened = openPort()
            synchronized(lock) {
                check(token == generation) { "Lifecycle-Abbruch." }
                port = opened
                val current = eligibility()
                current.check()
                check(current.connection == connection) { "Geräteverbindung geändert." }
                VerifiedGain41Reference.validate(VerifiedGain41Reference.bytes())
                log("SEND_ATTEMPT", "sendVerifiedSol100OdGain41Probe Sol 100 OD Gain-Index 0 Zielwert 41 Länge 34 SHA-256 ${VerifiedGain41Reference.SHA256} Sendecalls 1")
                calls = 1 // Includes an Android call that throws.
                opened.sendVerifiedGain41()
                success = true
                log("SEND_SUCCESS", "Sendecalls $calls; Android hat Bytes angenommen; Display manuell prüfen.")
            }
        } catch (error: Exception) {
            failure = "${error.message} Es wurde kein weiterer Sendeversuch durchgeführt."
            synchronized(lock) { log("SEND_FAILED", "$failure Sendecalls $calls") }
        } finally {
            synchronized(lock) {
                if (opened != null) {
                    val closed = runCatching { opened.close() }
                    log("PORT_CLOSED", "Sendecalls $calls geschlossen=${closed.isSuccess}")
                    if (closed.isFailure) {
                        success = false
                        failure = "Portschluss fehlgeschlagen. Es wurde kein weiterer Sendeversuch durchgeführt."
                        log("SEND_FAILED", requireNotNull(failure))
                    }
                }
                port = null
            }
            inProgress.set(false)
        }
        return status() + mapOf("success" to success, "error" to failure, "sendCalls" to calls)
    }
    fun cancel() = synchronized(lock) {
        ++generation
        port?.let { log("PORT_CLOSED", "Lifecycle-Abbruch geschlossen=${runCatching { it.close() }.isSuccess}") }
        port = null
    }
    fun detached(connection: String?) = synchronized(lock) {
        cancel()
        if (connection != null) attemptedConnections.remove(connection)
    }
}
