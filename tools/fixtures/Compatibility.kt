import dev.peringer.limen.data.*
import kotlinx.serialization.json.Json
import java.io.File
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

fun main(args: Array<String>) {
  val out = File(args[0]).apply { mkdirs() }
  // Fixed randomness belongs only to a deterministic test vector, never ArchiveCrypto.export.
  val salt = ByteArray(16) { (it * 7 + 1).toByte() }
  val iv = ByteArray(12) { (it * 11 + 3).toByte() }
  val header = "LIMENSAFE".toByteArray() + byteArrayOf(1) + salt + iv
  val plain = ByteArray(700_003) { ((it * 31 + 7) and 255).toByte() }
  val key = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(PBEKeySpec("päss 🔐".toCharArray(), salt, 210000, 256)).encoded
  val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
    init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, iv)); updateAAD(header)
  }
  File(out, "crypto-vector.limen").writeBytes(header + cipher.doFinal(plain))
  File(out, "crypto-key.hex").writeText(key.joinToString("") { "%02X".format(it) })
  val full = Json { encodeDefaults = true }
  val compact = Json { encodeDefaults = false }
  val root = File(out, "android-store").apply { mkdirs() }
  val store = Store(root)
  val input = File(out, "input.json")
  val p = compact.decodeFromString<Protocol>(input.readText())
  val records = listOf(
    p.copy(id = "draft", finalizedEpochMs = 0, evidenceFingerprint = "", exportHistory = emptyList(), saveSequence = 1),
    p.copy(id = "final", finalizedEpochMs = 1791885600000, exportHistory = emptyList(), saveSequence = 2),
    p.copy(id = "delivered", finalizedEpochMs = 1791885600000, saveSequence = 3),
    p.copy(id = "amendment", finalizedEpochMs = 0, evidenceFingerprint = "", amendedFromId = "final", amendedFromFingerprint = "fixture-original", exportHistory = emptyList(), saveSequence = 1)
  )
  records.forEach { original ->
    val photos = store.photoDir(original.id); val ink = store.signatureDir(original.id)
    File(out, "assets").listFiles()!!.forEach { it.copyTo(File(if (it.name == "ink.png") ink else photos, it.name), overwrite = true) }
    var r = original.copy(
      details = original.details.copy(attachments = original.details.attachments.map { a -> a.copy(bytes = File(photos, a.file).length(), sha256 = ProtocolIntegrity.fileHash(File(photos, a.file))) }),
      exportHistory = original.exportHistory.map { e ->
        val dir = File(root, "exports/${original.id}").apply { mkdirs() }
        listOf(e.name, e.name.removeSuffix(".pdf") + ".html").forEach { name -> File(out, "assets/$name").copyTo(File(dir, name), overwrite = true) }
        e.copy(bytes = File(dir, e.name).length(), sha256 = ProtocolIntegrity.fileHash(File(dir, e.name)))
      })
    if (r.finalizedEpochMs > 0) r = r.copy(evidenceFingerprint = ProtocolIntegrity.fingerprint(r, photos, ink))
    store.save(r)
    File(out, "${r.id}.canonical.json").writeText(full.encodeToString(Protocol.serializer(), r))
    File(out, "${r.id}.stored.json").writeText(compact.encodeToString(Protocol.serializer(), r))
    File(out, "${r.id}.fingerprint.txt").writeText(ProtocolIntegrity.fingerprint(r, photos, ink))
  }
  File(out, "android.zip").outputStream().use { store.exportArchive(charArrayOf(), it) }
  File(out, "android.limen").outputStream().use { store.exportArchive("päss 🔐".toCharArray(), it) }
  if (args.size > 1) {
    val swift = File(args[1])
    listOf("swift.zip", "swift.limen").forEach { name ->
      val restored = Store(File(out, "verified-$name"))
      val result = File(swift, name).inputStream().use { restored.importArchive("päss 🔐".toCharArray(), it) }
      check(result.imported == 4) { "$name: $result" }
      restored.list().forEach { r ->
        check(full.encodeToString(Protocol.serializer(), r) == File(out, "${r.id}.canonical.json").readText())
        check(ProtocolIntegrity.fingerprint(r, File(out, "verified-$name/photos/${r.id}"), File(out, "verified-$name/signatures/${r.id}")) == File(out, "${r.id}.fingerprint.txt").readText())
      }
      val returned = if (name.endsWith(".limen")) "jvm-return.limen" else "jvm-return.zip"
      File(out, returned).outputStream().use { restored.exportArchive(if (name.endsWith(".limen")) "päss 🔐".toCharArray() else charArrayOf(), it) }
      println("Verified Swift -> JVM: $name, four canonical records and fingerprints; wrote $returned")
    }
  }
  println("Generated JVM fixtures from real Android constructors/archive implementation")
}
