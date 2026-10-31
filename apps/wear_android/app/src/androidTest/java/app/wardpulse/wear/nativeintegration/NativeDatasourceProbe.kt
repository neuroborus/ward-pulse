package app.wardpulse.wear.nativeintegration

import java.io.File
import org.json.JSONObject

/** The scope digest includes caller, resource/runtime, System, full-eight native and owned-Push evidence. */
internal data class NativeDatasourceProbeScope(
    val hostApkSha256: String,
    val instanceSha256: String,
    val configurationSha256: String,
    val mappingSha256: String,
    val scopeSha256: String,
) {
    fun json() = JSONObject().put("hostApkSha256", hostApkSha256).put("instanceSha256", instanceSha256)
        .put("configurationSha256", configurationSha256).put("mappingSha256", mappingSha256)
        .put("scopeSha256", scopeSha256)
}

internal data class NativeDatasourceProbeSelection(val id: String, val receiptSha256: String, val frameSha256: String)

/** Explicit immutable selection only. Never consult, migrate or repair the historical probe directory. */
internal class NativeDatasourceProbe(root: File, val id: String) {
    private val probes = File(root, "probes")
    val directory: File

    init {
        nativeGuard(id.matches(Regex("[a-z0-9][a-z0-9_-]{0,63}")), "explicit-delivery-probe-id")
        directory = File(probes, id)
        nativeGuard(probes.canonicalFile == File(root.canonicalFile, "probes") &&
            directory.canonicalFile == File(probes.canonicalFile, id), "delivery-probe-path")
    }

    /** A partial capture consumes the ID too; no second invocation can replace its evidence. */
    fun create(scope: NativeDatasourceProbeScope, capture: (File) -> Unit,
        currentScope: () -> NativeDatasourceProbeScope) {
        requireScope(scope)
        nativeGuard(probes.isDirectory || probes.mkdirs(), "private-delivery-probes-directory")
        nativeGuard(directory.mkdir(), "fresh-delivery-probe")
        capture(directory)
        val frame = original("first.png")
        val record = original("first.json")
        requireRecord(record, scope)
        nativeGuard(currentScope() == scope, "delivery-probe-scope-changed")
        val receipt = scope.json().put("deliveryProbeId", id).put("frameReview", "Pending")
            .put("state", "first original recorded; independent review Pending")
            .put("frameSha256", frame.inputStream().sha256())
            .put("nativeRecordSha256", record.inputStream().sha256())
        val file = File(directory, "receipt.json")
        nativeGuard(file.createNewFile(), "single-delivery-probe-receipt")
        file.outputStream().use {
            it.write(receipt.toString().toByteArray(Charsets.UTF_8))
            it.flush()
            it.fd.sync()
        }
    }

    /** This verifies selected evidence, not the HOST's visual review, quiet custody or write authority. */
    fun reviewed(scope: NativeDatasourceProbeScope, receiptSha256: String,
        frameSha256: String): NativeDatasourceProbeSelection {
        requireScope(scope)
        nativeGuard(listOf(receiptSha256, frameSha256).all { it.matches(Regex("[a-f0-9]{64}")) },
            "delivery-probe-review-hashes")
        val bytes = original("receipt.json").readBytes()
        nativeGuard(bytes.inputStream().sha256() == receiptSha256, "reviewed-delivery-probe-receipt")
        val receipt = JSONObject(bytes.toString(Charsets.UTF_8))
        nativeGuard(receipt.opt("deliveryProbeId") == id && receipt.opt("frameReview") == "Pending" &&
            receipt.opt("state") == "first original recorded; independent review Pending", "complete-delivery-probe")
        val current = scope.json()
        current.keys().forEach { key ->
            nativeGuard(receipt.opt(key) == current.get(key), "reviewed-delivery-probe-scope")
        }
        nativeGuard(receipt.opt("frameSha256") == frameSha256 &&
            original("first.png").inputStream().sha256() == frameSha256, "reviewed-first-original")
        val record = original("first.json")
        nativeGuard(record.inputStream().sha256() == receipt.opt("nativeRecordSha256"),
            "reviewed-delivery-probe-native-record")
        requireRecord(record, scope)
        return NativeDatasourceProbeSelection(id, receiptSha256, frameSha256)
    }

    private fun requireScope(scope: NativeDatasourceProbeScope) {
        val json = scope.json()
        nativeGuard(json.keys().asSequence().all { json.getString(it).matches(Regex("[a-f0-9]{64}")) },
            "complete-delivery-probe-scope")
    }

    private fun original(name: String): File = File(directory, name).also { file ->
        // AtomicFile sidecars are ambiguous evidence, not permission to repair or pick a newer copy.
        nativeGuard(file.isFile && file.length() > 0 && file.canonicalFile == File(directory.canonicalFile, name) &&
            !File("${file.path}.bak").exists() && !File("${file.path}.new").exists(),
            "complete-single-delivery-probe-original")
    }

    private fun requireRecord(file: File, scope: NativeDatasourceProbeScope) {
        val record = JSONObject(file.readText())
        nativeGuard(record.opt("instanceSha256") == scope.instanceSha256 &&
            record.opt("configurationSha256") == scope.configurationSha256 &&
            record.opt("nativeRecordAcquired") == "before frame" && record.optJSONObject("effectiveData") != null &&
            record.opt("responseProvenance") == "Pending" && record.opt("visualAcceptance") == "Pending",
            "delivery-probe-native-record-scope")
    }
}
