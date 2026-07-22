package com.example.geneapp.bluemagpie

import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.security.MessageDigest
import org.json.JSONObject

data class ModelManifest(
    val repository: String,
    val revision: String,
    val conversionLicense: String,
    val conversionLicenseUrl: String,
    val upstreamRepository: String,
    val upstreamRevision: String,
    val upstreamLicense: String,
    val upstreamLicenseUrl: String,
    val licenseReviewRequired: Boolean,
    val architectureProvenanceUrl: String,
    val minimumFreeBytes: Long,
    val models: List<ModelDescriptor>,
)

data class ModelDescriptor(
    val id: String,
    val filename: String,
    val byteSize: Long,
    val sha256: String,
    val provenanceUrl: String,
)

object ModelManifestParser {
    private val immutableRevision = Regex("^[0-9a-f]{40}$")
    private val sha256 = Regex("^[0-9a-f]{64}$")
    private val safeName = Regex("^[A-Za-z0-9][A-Za-z0-9._-]*$")

    fun parse(json: String): ModelManifest {
        val root = JSONObject(json)
        val revision = root.getString("revision")
        require(immutableRevision.matches(revision)) { "Model revision must be an immutable commit SHA." }

        val repository = root.getString("repository")
        require(repository.matches(Regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$"))) {
            "Model repository must be an owner/name identifier."
        }
        val conversionLicenseUrl = root.getString("conversionLicenseUrl")
        val upstreamLicenseUrl = root.getString("upstreamLicenseUrl")
        val architectureProvenanceUrl = root.getString("architectureProvenanceUrl")
        require(isHttpsUrl(conversionLicenseUrl)) { "Conversion license URL must use HTTPS." }
        require(isHttpsUrl(upstreamLicenseUrl)) { "Upstream license URL must use HTTPS." }
        require(isHttpsUrl(architectureProvenanceUrl)) { "Architecture provenance URL must use HTTPS." }
        val upstreamRevision = root.getString("upstreamRevision")
        require(immutableRevision.matches(upstreamRevision)) {
            "Upstream model revision must be an immutable commit SHA."
        }
        val upstreamRepository = root.getString("upstreamRepository")
        require(upstreamRepository.matches(Regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$"))) {
            "Upstream repository must be an owner/name identifier."
        }
        val conversionLicense = root.getString("conversionLicense").also { require(it.isNotBlank()) }
        val upstreamLicense = root.getString("upstreamLicense").also { require(it.isNotBlank()) }
        val licenseReviewRequired = root.getBoolean("licenseReviewRequired")
        require(licenseReviewRequired || conversionLicense == upstreamLicense) {
            "License review cannot be waived when upstream and conversion licenses differ."
        }
        val minimumFreeBytes = root.getLong("minimumFreeBytes")
        require(minimumFreeBytes > 0) { "Minimum free space must be positive." }

        val entries = root.getJSONArray("models")
        require(entries.length() > 0) { "Model manifest must contain at least one model." }
        val models =
            (0 until entries.length()).map { index ->
                val entry = entries.getJSONObject(index)
                val descriptor =
                    ModelDescriptor(
                        id = entry.getString("id"),
                        filename = entry.getString("filename"),
                        byteSize = entry.getLong("byteSize"),
                        sha256 = entry.getString("sha256"),
                        provenanceUrl = entry.getString("provenanceUrl"),
                    )
                require(safeName.matches(descriptor.id)) { "Model ID is invalid." }
                require(safeName.matches(descriptor.filename)) { "Model filename must be a basename." }
                require(descriptor.byteSize > 0) { "Model byte size must be positive." }
                require(sha256.matches(descriptor.sha256)) { "Model SHA-256 must be lowercase hexadecimal." }
                require(isHttpsUrl(descriptor.provenanceUrl)) { "Model provenance URL must use HTTPS." }
                descriptor
            }
        require(models.map { it.id }.distinct().size == models.size) { "Model IDs must be unique." }
        require(models.map { it.filename }.distinct().size == models.size) { "Model filenames must be unique." }

        return ModelManifest(
            repository = repository,
            revision = revision,
            conversionLicense = conversionLicense,
            conversionLicenseUrl = conversionLicenseUrl,
            upstreamRepository = upstreamRepository,
            upstreamRevision = upstreamRevision,
            upstreamLicense = upstreamLicense,
            upstreamLicenseUrl = upstreamLicenseUrl,
            licenseReviewRequired = licenseReviewRequired,
            architectureProvenanceUrl = architectureProvenanceUrl,
            minimumFreeBytes = minimumFreeBytes,
            models = models,
        )
    }

    private fun isHttpsUrl(value: String): Boolean =
        value.startsWith("https://") && !value.contains(' ') && value.length > "https://".length
}

enum class ModelValidationCode(val wireValue: String) {
    READY("ready"),
    MODEL_MISSING("model_missing"),
    MODEL_PATH_REJECTED("model_path_rejected"),
    MODEL_SIZE_MISMATCH("model_size_mismatch"),
    MODEL_CHECKSUM_MISMATCH("model_checksum_mismatch"),
    INSUFFICIENT_SPACE("insufficient_space"),
    IO_FAILED("io_failed"),
}

data class ModelValidationItem(
    val modelId: String,
    val filename: String,
    val code: ModelValidationCode,
)

data class ModelValidationResult(
    val code: ModelValidationCode,
    val safeMessage: String,
    val models: List<ModelValidationItem>,
    val freeBytes: Long? = null,
    val minimumFreeBytes: Long? = null,
) {
    val isReady: Boolean
        get() = code == ModelValidationCode.READY

    val failedModelId: String?
        get() = models.firstOrNull { it.code != ModelValidationCode.READY }?.modelId
}

data class FileProbe(
    val exists: Boolean,
    val readable: Boolean,
    val byteSize: Long,
    val sha256: String?,
)

fun interface ModelFileInspector {
    @Throws(IOException::class)
    fun probe(file: File, descriptor: ModelDescriptor): FileProbe
}

class Sha256ModelFileInspector : ModelFileInspector {
    override fun probe(file: File, descriptor: ModelDescriptor): FileProbe {
        if (!file.exists() || !file.isFile) {
            return FileProbe(exists = false, readable = false, byteSize = 0, sha256 = null)
        }
        if (!file.canRead()) {
            return FileProbe(exists = true, readable = false, byteSize = file.length(), sha256 = null)
        }
        val length = file.length()
        if (length != descriptor.byteSize) {
            return FileProbe(exists = true, readable = true, byteSize = length, sha256 = null)
        }
        return FileProbe(
            exists = true,
            readable = true,
            byteSize = length,
            sha256 = digest(file),
        )
    }

    private fun digest(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).buffered().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    }
}

class ModelValidator(
    private val manifest: ModelManifest,
    private val inspector: ModelFileInspector = Sha256ModelFileInspector(),
    private val freeBytesProvider: () -> Long,
) {
    fun validate(privateModelDirectory: File): ModelValidationResult =
        validate(
            privateModelDirectory,
            manifest.models.associate { descriptor ->
                descriptor.id to File(privateModelDirectory, descriptor.filename)
            },
        )

    internal fun validate(
        privateModelDirectory: File,
        candidatePaths: Map<String, File>,
    ): ModelValidationResult {
        val canonicalRoot =
            try {
                privateModelDirectory.canonicalFile
            } catch (_: IOException) {
                return failure(ModelValidationCode.MODEL_PATH_REJECTED, null)
            } catch (_: SecurityException) {
                return failure(ModelValidationCode.MODEL_PATH_REJECTED, null)
            }

        val validatedPaths = mutableMapOf<String, File>()
        for (descriptor in manifest.models) {
            val candidate = candidatePaths[descriptor.id]
                ?: return failure(ModelValidationCode.MODEL_PATH_REJECTED, descriptor)
            val canonicalCandidate =
                try {
                    candidate.canonicalFile
                } catch (_: IOException) {
                    return failure(ModelValidationCode.MODEL_PATH_REJECTED, descriptor)
                } catch (_: SecurityException) {
                    return failure(ModelValidationCode.MODEL_PATH_REJECTED, descriptor)
                }
            val expected =
                try {
                    File(canonicalRoot, descriptor.filename).canonicalFile
                } catch (_: IOException) {
                    return failure(ModelValidationCode.MODEL_PATH_REJECTED, descriptor)
                } catch (_: SecurityException) {
                    return failure(ModelValidationCode.MODEL_PATH_REJECTED, descriptor)
                }
            if (canonicalCandidate != expected || canonicalCandidate.parentFile != canonicalRoot) {
                return failure(ModelValidationCode.MODEL_PATH_REJECTED, descriptor)
            }
            validatedPaths[descriptor.id] = canonicalCandidate
        }

        val items = mutableListOf<ModelValidationItem>()
        for (descriptor in manifest.models) {
            val probe =
                try {
                    inspector.probe(validatedPaths.getValue(descriptor.id), descriptor)
                } catch (_: IOException) {
                    return failure(ModelValidationCode.IO_FAILED, descriptor, items)
                } catch (_: SecurityException) {
                    return failure(ModelValidationCode.IO_FAILED, descriptor, items)
                }
            val code =
                when {
                    !probe.exists || !probe.readable -> ModelValidationCode.MODEL_MISSING
                    probe.byteSize != descriptor.byteSize -> ModelValidationCode.MODEL_SIZE_MISMATCH
                    probe.sha256 != descriptor.sha256 -> ModelValidationCode.MODEL_CHECKSUM_MISMATCH
                    else -> ModelValidationCode.READY
                }
            items += ModelValidationItem(descriptor.id, descriptor.filename, code)
            if (code != ModelValidationCode.READY) {
                return result(code, descriptor, items)
            }
        }

        val freeBytes =
            try {
                freeBytesProvider().coerceAtLeast(0)
            } catch (_: SecurityException) {
                return failure(ModelValidationCode.IO_FAILED, null, items)
            } catch (_: IOException) {
                return failure(ModelValidationCode.IO_FAILED, null, items)
            }
        if (freeBytes < manifest.minimumFreeBytes) {
            return ModelValidationResult(
                code = ModelValidationCode.INSUFFICIENT_SPACE,
                safeMessage = "Not enough application-private storage is available for synthesis output.",
                models = items,
                freeBytes = freeBytes,
                minimumFreeBytes = manifest.minimumFreeBytes,
            )
        }
        return ModelValidationResult(
            code = ModelValidationCode.READY,
            safeMessage = "All required model files passed validation.",
            models = items,
            freeBytes = freeBytes,
            minimumFreeBytes = manifest.minimumFreeBytes,
        )
    }

    private fun failure(
        code: ModelValidationCode,
        descriptor: ModelDescriptor?,
        priorItems: List<ModelValidationItem> = emptyList(),
    ): ModelValidationResult = result(code, descriptor, priorItems)

    private fun result(
        code: ModelValidationCode,
        descriptor: ModelDescriptor?,
        priorItems: List<ModelValidationItem>,
    ): ModelValidationResult {
        val items = priorItems.toMutableList()
        if (descriptor != null && items.none { it.modelId == descriptor.id }) {
            items += ModelValidationItem(descriptor.id, descriptor.filename, code)
        }
        return ModelValidationResult(
            code = code,
            safeMessage = safeMessage(code, descriptor?.id),
            models = items,
        )
    }

    private fun safeMessage(code: ModelValidationCode, modelId: String?): String {
        val subject = modelId?.let { "Model '$it'" } ?: "Model validation"
        return when (code) {
            ModelValidationCode.MODEL_MISSING -> "$subject is missing or unreadable."
            ModelValidationCode.MODEL_PATH_REJECTED -> "$subject is outside application-private model storage."
            ModelValidationCode.MODEL_SIZE_MISMATCH -> "$subject does not match the pinned byte size."
            ModelValidationCode.MODEL_CHECKSUM_MISMATCH -> "$subject failed SHA-256 verification."
            ModelValidationCode.INSUFFICIENT_SPACE -> "Not enough application-private storage is available."
            ModelValidationCode.IO_FAILED -> "$subject could not be verified due to an I/O error."
            ModelValidationCode.READY -> "Model validation completed."
        }
    }
}
