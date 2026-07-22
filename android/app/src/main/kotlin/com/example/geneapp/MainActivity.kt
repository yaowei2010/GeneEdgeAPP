package com.example.geneapp

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import kotlin.math.ceil
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val channelName = "geneedge/taigi_asr"

    private external fun nativeTranscribe(modelPath: String, wavPath: String): String

    companion object {
        init {
            System.loadLibrary("geneedge_whisper")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "recordWav" -> {
                        val seconds = call.argument<Int>("durationSeconds") ?: 5
                        recordWav(seconds, result)
                    }
                    "transcribeWav" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_PATH", "Missing WAV path.", null)
                            return@setMethodCallHandler
                        }
                        transcribeWav(path, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun recordWav(durationSeconds: Int, result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            result.error("NO_MIC_PERMISSION", "Microphone permission is required for offline Taigi ASR recording.", null)
            return
        }

        val safeSeconds = durationSeconds.coerceIn(1, 15)
        thread(name = "geneedge-taigi-wav-recorder") {
            try {
                val path = recordPcm16MonoWav(safeSeconds)
                runOnUiThread { result.success(path) }
            } catch (e: Exception) {
                runOnUiThread {
                    result.error("RECORDING_FAILED", e.message ?: "Recording failed.", null)
                }
            }
        }
    }

    private fun transcribeWav(path: String, result: MethodChannel.Result) {
        val wav = File(path)
        if (!wav.exists()) {
            result.error("INVALID_PATH", "WAV file does not exist.", path)
            return
        }

        val model = defaultModelFile()
        if (!model.exists()) {
            result.success(
                mapOf(
                    "text" to "",
                    "engineInstalled" to false,
                    "message" to "Missing offline Breeze-ASR GGML model. Put the model at: ${model.absolutePath}"
                )
            )
            return
        }

        thread(name = "geneedge-taigi-asr") {
            try {
                val text = nativeTranscribe(model.absolutePath, wav.absolutePath).trim()
                runOnUiThread {
                    result.success(
                        mapOf(
                            "text" to text,
                            "engineInstalled" to true,
                            "message" to if (text.isEmpty()) {
                                "Offline ASR completed, but no speech text was detected."
                            } else {
                                "Offline Breeze-ASR transcription completed."
                            }
                        )
                    )
                }
            } catch (e: Exception) {
                runOnUiThread {
                    result.success(
                        mapOf(
                            "text" to "",
                            "engineInstalled" to true,
                            "message" to "Offline ASR failed: ${e.message ?: "unknown native error"}"
                        )
                    )
                }
            }
        }
    }

    private fun defaultModelFile(): File {
        val modelDir = File(getExternalFilesDir(null), "models")
        return File(modelDir, "breeze-asr-26.ggml.bin")
    }

    private fun recordPcm16MonoWav(durationSeconds: Int): String {
        val sampleRate = 16000
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val minBuffer = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        require(minBuffer > 0) { "Unsupported AudioRecord configuration." }

        val output = File(cacheDir, "taigi_asr_input.wav")
        val recorder = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            sampleRate,
            channelConfig,
            audioFormat,
            minBuffer * 2
        )
        require(recorder.state == AudioRecord.STATE_INITIALIZED) {
            "AudioRecord failed to initialize."
        }

        var totalAudioBytes = 0L
        RandomAccessFile(output, "rw").use { wav ->
            wav.setLength(0)
            writeWavHeader(wav, sampleRate, 0)
            val buffer = ByteArray(minBuffer)
            val targetBytes = sampleRate * durationSeconds * 2
            val startedAt = System.currentTimeMillis()
            val timeoutMs = ceil(durationSeconds * 2500.0).toLong().coerceAtLeast(8000L)
            recorder.startRecording()
            try {
                while (totalAudioBytes < targetBytes) {
                    if (System.currentTimeMillis() - startedAt > timeoutMs) {
                        throw IllegalStateException("Recording timed out after ${timeoutMs}ms.")
                    }
                    val remaining = (targetBytes - totalAudioBytes).toInt()
                    val readSize = minOf(buffer.size, remaining)
                    val read = recorder.read(buffer, 0, readSize)
                    when {
                        read > 0 -> {
                            wav.write(buffer, 0, read)
                            totalAudioBytes += read.toLong()
                        }
                        read < 0 -> {
                            throw IllegalStateException("AudioRecord read failed with code $read.")
                        }
                    }
                }
            } finally {
                if (recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    recorder.stop()
                }
                recorder.release()
            }
            wav.seek(0)
            writeWavHeader(wav, sampleRate, totalAudioBytes)
        }
        return output.absolutePath
    }

    private fun writeWavHeader(wav: RandomAccessFile, sampleRate: Int, audioBytes: Long) {
        val byteRate = sampleRate * 2
        val totalDataLen = audioBytes + 36
        wav.writeBytes("RIFF")
        writeIntLE(wav, totalDataLen.toInt())
        wav.writeBytes("WAVE")
        wav.writeBytes("fmt ")
        writeIntLE(wav, 16)
        writeShortLE(wav, 1)
        writeShortLE(wav, 1)
        writeIntLE(wav, sampleRate)
        writeIntLE(wav, byteRate)
        writeShortLE(wav, 2)
        writeShortLE(wav, 16)
        wav.writeBytes("data")
        writeIntLE(wav, audioBytes.toInt())
    }

    private fun writeIntLE(file: RandomAccessFile, value: Int) {
        file.write(value and 0xff)
        file.write((value shr 8) and 0xff)
        file.write((value shr 16) and 0xff)
        file.write((value shr 24) and 0xff)
    }

    private fun writeShortLE(file: RandomAccessFile, value: Int) {
        file.write(value and 0xff)
        file.write((value shr 8) and 0xff)
    }
}
