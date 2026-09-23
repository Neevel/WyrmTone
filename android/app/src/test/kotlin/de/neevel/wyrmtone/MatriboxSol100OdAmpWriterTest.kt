package de.neevel.wyrmtone

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class MatriboxSol100OdAmpWriterTest {
    private fun bytes(hex: String): ByteArray =
        ByteArray(hex.length / 2) { i -> hex.substring(i * 2, i * 2 + 2).toInt(16).toByte() }

    // Real host->device messages extracted programmatically from the original
    // matribox1_p01_store.pcapng (generated from the same fixture list as the
    // Dart test; no hand transcription).
    private val captured = listOf(
        Triple(Sol100OdAmpField.GAIN, 29.0f, "f021257f514d45321210030002040700000000000700000000000000000e080401f7"),
        Triple(Sol100OdAmpField.GAIN, 23.0f, "f021257f514d45321210030002040700000000000700000000000000000b080401f7"),
        Triple(Sol100OdAmpField.GAIN, 17.0f, "f021257f514d453212100300020407000000000007000000000000000008080401f7"),
        Triple(Sol100OdAmpField.PRESENCE, 51.0f, "f021257f514d4532121003000204070000000000070001000000000000040c0402f7"),
        Triple(Sol100OdAmpField.PRESENCE, 62.0f, "f021257f514d453212100300020407000000000007000100000000000007080402f7"),
        Triple(Sol100OdAmpField.PRESENCE, 73.0f, "f021257f514d453212100300020407000000000007000100000000000009020402f7"),
        Triple(Sol100OdAmpField.VOLUME, 49.0f, "f021257f514d453212100300020407000000000007000200000000000004040402f7"),
        Triple(Sol100OdAmpField.VOLUME, 48.0f, "f021257f514d453212100300020407000000000007000200000000000004000402f7"),
        Triple(Sol100OdAmpField.VOLUME, 47.0f, "f021257f514d4532121003000204070000000000070002000000000000030c0402f7"),
        Triple(Sol100OdAmpField.BASS, 49.0f, "f021257f514d453212100300020407000000000007000300000000000004040402f7"),
        Triple(Sol100OdAmpField.BASS, 35.0f, "f021257f514d4532121003000204070000000000070003000000000000000c0402f7"),
        Triple(Sol100OdAmpField.BASS, 23.0f, "f021257f514d45321210030002040700000000000700030000000000000b080401f7"),
        Triple(Sol100OdAmpField.MIDDLE, 49.0f, "f021257f514d453212100300020407000000000007000400000000000004040402f7"),
        Triple(Sol100OdAmpField.MIDDLE, 59.0f, "f021257f514d4532121003000204070000000000070004000000000000060c0402f7"),
        Triple(Sol100OdAmpField.MIDDLE, 67.0f, "f021257f514d453212100300020407000000000007000400000000000008060402f7"),
        Triple(Sol100OdAmpField.TREBLE, 51.0f, "f021257f514d4532121003000204070000000000070005000000000000040c0402f7"),
        Triple(Sol100OdAmpField.TREBLE, 42.0f, "f021257f514d453212100300020407000000000007000500000000000002080402f7"),
        Triple(Sol100OdAmpField.TREBLE, 31.0f, "f021257f514d45321210030002040700000000000700050000000000000f080401f7"),
    )

    @Test fun `reproduces every real captured message byte-for-byte for all six fields`() {
        assertEquals(setOf("gain", "presence", "volume", "bass", "middle", "treble"), captured.map { it.first.wireName }.toSet())
        for ((field, value, hex) in captured) {
            assertArrayEquals("${field.wireName}=$value", bytes(hex), MatriboxSol100OdAmpWriter.encode(field, value))
            MatriboxSol100OdAmpWriter.validate(field, bytes(hex))
        }
    }

    @Test fun `Gain output equals the already hardware-certified Gain writer`() {
        for (value in listOf(0f, 17f, 18f, 41f, 99f)) {
            assertArrayEquals(
                MatriboxConfirmedGainWriter.encode(value),
                MatriboxSol100OdAmpWriter.encode(Sol100OdAmpField.GAIN, value),
            )
        }
    }

    @Test fun `field whitelist is closed and indices match the capture`() {
        assertEquals(listOf(0, 1, 2, 3, 4, 5), Sol100OdAmpField.values().map { it.parameterIndex })
        assertEquals(null, Sol100OdAmpField.fromWireName("reverb"))
        assertEquals(null, Sol100OdAmpField.fromWireName("GAIN"))
        assertEquals(null, Sol100OdAmpField.fromWireName(""))
        assertTrue(Sol100OdAmpField.GAIN !in Sol100OdAmpField.CERTIFICATION_FIELDS)
        assertEquals(5, Sol100OdAmpField.CERTIFICATION_FIELDS.size)
    }

    @Test fun `rejects out-of-range and non-finite values`() {
        for (v in listOf(-1f, 100f, Float.NaN, Float.POSITIVE_INFINITY)) {
            assertThrows(IllegalArgumentException::class.java) {
                MatriboxSol100OdAmpWriter.encode(Sol100OdAmpField.PRESENCE, v)
            }
        }
    }

    @Test fun `validate rejects a message whose index does not match the field`() {
        val presence = MatriboxSol100OdAmpWriter.encode(Sol100OdAmpField.PRESENCE, 74f)
        assertThrows(IllegalArgumentException::class.java) {
            MatriboxSol100OdAmpWriter.validate(Sol100OdAmpField.VOLUME, presence)
        }
        val tampered = presence.copyOf().also { it[13] = 0x09 }
        assertThrows(IllegalArgumentException::class.java) {
            MatriboxSol100OdAmpWriter.validate(Sol100OdAmpField.PRESENCE, tampered)
        }
    }
}
