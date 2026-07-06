package com.nasserver.nas_server

import android.content.Context
import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.asn1.x509.BasicConstraints
import org.bouncycastle.asn1.x509.Extension
import org.bouncycastle.asn1.x509.ExtendedKeyUsage
import org.bouncycastle.asn1.x509.GeneralName
import org.bouncycastle.asn1.x509.GeneralNames
import org.bouncycastle.asn1.x509.KeyPurposeId
import org.bouncycastle.asn1.x509.KeyUsage
import org.bouncycastle.cert.X509CertificateHolder
import org.bouncycastle.cert.X509v3CertificateBuilder
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter
import org.bouncycastle.cert.jcajce.JcaX509ExtensionUtils
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder
import org.bouncycastle.jce.provider.BouncyCastleProvider
import org.bouncycastle.operator.ContentSigner
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder
import org.bouncycastle.util.io.pem.PemObject
import org.bouncycastle.util.io.pem.PemWriter
import org.json.JSONObject
import java.io.File
import java.io.StringWriter
import java.math.BigInteger
import java.security.KeyFactory
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.SecureRandom
import java.security.Security
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.security.spec.PKCS8EncodedKeySpec
import java.util.Date
import java.util.concurrent.TimeUnit

class NativeTlsMaterialService(
    context: Context,
) {
    companion object {
        private const val TLS_DIRECTORY = "tls"
        private const val ROOT_CA_CERT_FILE = "root_ca_cert.pem"
        private const val ROOT_CA_KEY_FILE = "root_ca_key.pem"
        private const val LEAF_CERT_FILE = "server_leaf_cert.pem"
        private const val LEAF_KEY_FILE = "server_leaf_key.pem"
        private const val METADATA_FILE = "tls_metadata_native.json"
        private const val METADATA_VERSION = 2
        private const val ROOT_VALIDITY_DAYS = 3650L
        private const val LEAF_VALIDITY_DAYS = 825L
        private const val EC_CURVE_NAME = "secp256r1"
        private val SECURE_RANDOM = SecureRandom()

        init {
            val currentProvider = Security.getProvider(BouncyCastleProvider.PROVIDER_NAME)
            if (currentProvider == null || currentProvider.javaClass != BouncyCastleProvider::class.java) {
                Security.removeProvider(BouncyCastleProvider.PROVIDER_NAME)
                Security.insertProviderAt(BouncyCastleProvider(), 1)
            }
        }
    }

    private val appContext = context.applicationContext
    private val certificateFactory = CertificateFactory.getInstance("X.509")
    private val certificateConverter =
        JcaX509CertificateConverter().setProvider(BouncyCastleProvider.PROVIDER_NAME)

    fun ensureTlsMaterial(
        serverId: String,
        hostLabel: String,
        localIp: String,
    ): Map<String, String> {
        val tlsDirectory = File(appContext.filesDir, TLS_DIRECTORY).apply {
            mkdirs()
        }
        val metadataFile = File(tlsDirectory, METADATA_FILE)
        val rootCaCertFile = File(tlsDirectory, ROOT_CA_CERT_FILE)
        val rootCaKeyFile = File(tlsDirectory, ROOT_CA_KEY_FILE)
        val leafCertFile = File(tlsDirectory, LEAF_CERT_FILE)
        val leafKeyFile = File(tlsDirectory, LEAF_KEY_FILE)

        val metadata = loadMetadata(metadataFile)
        val rootMaterial =
            if (metadata != null &&
                metadata.version == METADATA_VERSION &&
                metadata.serverId == serverId &&
                metadata.hostLabel == hostLabel &&
                rootCaCertFile.exists() &&
                rootCaKeyFile.exists()
            ) {
                loadRootMaterial(rootCaCertFile, rootCaKeyFile)
            } else {
                val generatedRoot = generateRootMaterial(serverId, hostLabel)
                rootCaCertFile.writeText(generatedRoot.certificatePem)
                rootCaKeyFile.writeText(generatedRoot.privateKeyPem)
                generatedRoot
            }

        val leafMaterial =
            if (metadata != null &&
                metadata.version == METADATA_VERSION &&
                metadata.serverId == serverId &&
                metadata.hostLabel == hostLabel &&
                metadata.localIp == localIp &&
                leafCertFile.exists() &&
                leafKeyFile.exists()
            ) {
                loadLeafMaterial(leafCertFile, leafKeyFile)
            } else {
                val generatedLeaf =
                    generateLeafMaterial(
                        serverId = serverId,
                        hostLabel = hostLabel,
                        localIp = localIp,
                        issuerCertificate = rootMaterial.certificate,
                        issuerPrivateKey = rootMaterial.keyPair.private,
                    )
                leafCertFile.writeText(generatedLeaf.certificatePem)
                leafKeyFile.writeText(generatedLeaf.privateKeyPem)
                generatedLeaf
            }

        saveMetadata(
            metadataFile = metadataFile,
            metadata =
                StoredTlsMetadata(
                    version = METADATA_VERSION,
                    serverId = serverId,
                    hostLabel = hostLabel,
                    localIp = localIp,
                ),
        )

        return mapOf(
            "hostLabel" to hostLabel,
            "rootCaPem" to rootMaterial.certificatePem,
            "leafCertificatePem" to leafMaterial.certificatePem,
            "leafPrivateKeyPem" to leafMaterial.privateKeyPem,
        )
    }

    private fun loadRootMaterial(
        certificateFile: File,
        privateKeyFile: File,
    ): RootMaterial {
        val certificatePem = certificateFile.readText()
        val privateKeyPem = privateKeyFile.readText()
        val certificate = loadCertificate(certificatePem)
        val privateKey = loadPrivateKey(privateKeyPem)
        val publicKey = certificate.publicKey
        return RootMaterial(
            certificate = certificate,
            keyPair = KeyPair(publicKey, privateKey),
            certificatePem = certificatePem,
            privateKeyPem = privateKeyPem,
        )
    }

    private fun loadLeafMaterial(
        certificateFile: File,
        privateKeyFile: File,
    ): LeafMaterial {
        val certificatePem = certificateFile.readText()
        val privateKeyPem = privateKeyFile.readText()
        loadCertificate(certificatePem)
        loadPrivateKey(privateKeyPem)
        return LeafMaterial(
            certificatePem = certificatePem,
            privateKeyPem = privateKeyPem,
        )
    }

    private fun generateRootMaterial(
        serverId: String,
        hostLabel: String,
    ): RootMaterial {
        val keyPair = generateEcKeyPair()
        val subject = X500Name("CN=NASServer $hostLabel Root CA, O=NASServer, OU=$serverId")
        val certificateBuilder =
            JcaX509v3CertificateBuilder(
                subject,
                nextSerialNumber(),
                notBefore(),
                notAfter(ROOT_VALIDITY_DAYS),
                subject,
                keyPair.public,
            )
        val extensionUtils = JcaX509ExtensionUtils()
        certificateBuilder.addExtension(Extension.basicConstraints, true, BasicConstraints(0))
        certificateBuilder.addExtension(
            Extension.keyUsage,
            true,
            KeyUsage(KeyUsage.keyCertSign or KeyUsage.cRLSign),
        )
        certificateBuilder.addExtension(
            Extension.subjectKeyIdentifier,
            false,
            extensionUtils.createSubjectKeyIdentifier(keyPair.public),
        )
        certificateBuilder.addExtension(
            Extension.authorityKeyIdentifier,
            false,
            extensionUtils.createAuthorityKeyIdentifier(keyPair.public),
        )
        val certificate = signCertificate(certificateBuilder, keyPair.private)
        return RootMaterial(
            certificate = certificate,
            keyPair = keyPair,
            certificatePem = pemEncode("CERTIFICATE", certificate.encoded),
            privateKeyPem = pemEncode("PRIVATE KEY", keyPair.private.encoded),
        )
    }

    private fun generateLeafMaterial(
        serverId: String,
        hostLabel: String,
        localIp: String,
        issuerCertificate: X509Certificate,
        issuerPrivateKey: java.security.PrivateKey,
    ): LeafMaterial {
        val keyPair = generateEcKeyPair()
        val subject = X500Name("CN=$hostLabel.local, O=NASServer, OU=$serverId")
        val issuer = X500Name.getInstance(issuerCertificate.subjectX500Principal.encoded)
        val certificateBuilder: X509v3CertificateBuilder =
            JcaX509v3CertificateBuilder(
                issuer,
                nextSerialNumber(),
                notBefore(),
                notAfter(LEAF_VALIDITY_DAYS),
                subject,
                keyPair.public,
            )
        val extensionUtils = JcaX509ExtensionUtils()
        certificateBuilder.addExtension(Extension.basicConstraints, true, BasicConstraints(false))
        certificateBuilder.addExtension(
            Extension.keyUsage,
            true,
            KeyUsage(KeyUsage.digitalSignature),
        )
        certificateBuilder.addExtension(
            Extension.extendedKeyUsage,
            false,
            ExtendedKeyUsage(KeyPurposeId.id_kp_serverAuth),
        )
        certificateBuilder.addExtension(
            Extension.subjectAlternativeName,
            false,
            GeneralNames(
                arrayOf(
                    GeneralName(GeneralName.dNSName, "$hostLabel.local"),
                    GeneralName(GeneralName.dNSName, "localhost"),
                    GeneralName(GeneralName.iPAddress, localIp),
                    GeneralName(GeneralName.iPAddress, "127.0.0.1"),
                ),
            ),
        )
        certificateBuilder.addExtension(
            Extension.subjectKeyIdentifier,
            false,
            extensionUtils.createSubjectKeyIdentifier(keyPair.public),
        )
        certificateBuilder.addExtension(
            Extension.authorityKeyIdentifier,
            false,
            extensionUtils.createAuthorityKeyIdentifier(issuerCertificate),
        )
        val certificate = signCertificate(certificateBuilder, issuerPrivateKey)
        return LeafMaterial(
            certificatePem = pemEncode("CERTIFICATE", certificate.encoded),
            privateKeyPem = pemEncode("PRIVATE KEY", keyPair.private.encoded),
        )
    }

    private fun signCertificate(
        certificateBuilder: X509v3CertificateBuilder,
        signingKey: java.security.PrivateKey,
    ): X509Certificate {
        val signer: ContentSigner =
            JcaContentSignerBuilder("SHA256withECDSA")
                .setProvider(BouncyCastleProvider.PROVIDER_NAME)
                .build(signingKey)
        val certificateHolder: X509CertificateHolder = certificateBuilder.build(signer)
        return certificateConverter.getCertificate(certificateHolder)
    }

    private fun generateEcKeyPair(): KeyPair {
        val keyPairGenerator = KeyPairGenerator.getInstance("EC")
        keyPairGenerator.initialize(ECGenParameterSpec(EC_CURVE_NAME), SECURE_RANDOM)
        return keyPairGenerator.generateKeyPair()
    }

    private fun loadCertificate(pem: String): X509Certificate {
        val bytes = pemToDer(pem)
        return certificateFactory.generateCertificate(bytes.inputStream()) as X509Certificate
    }

    private fun loadPrivateKey(pem: String): java.security.PrivateKey {
        val keyFactory = KeyFactory.getInstance("EC")
        val keySpec = PKCS8EncodedKeySpec(pemToDer(pem))
        return keyFactory.generatePrivate(keySpec)
    }

    private fun pemEncode(
        label: String,
        bytes: ByteArray,
    ): String {
        val writer = StringWriter()
        PemWriter(writer).use { pemWriter ->
            pemWriter.writeObject(PemObject(label, bytes))
        }
        return writer.toString()
    }

    private fun pemToDer(pem: String): ByteArray {
        return pem
            .lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("-----") }
            .joinToString(separator = "")
            .let { java.util.Base64.getDecoder().decode(it) }
    }

    private fun loadMetadata(metadataFile: File): StoredTlsMetadata? {
        if (!metadataFile.exists()) {
            return null
        }
        val raw = metadataFile.readText().trim()
        if (raw.isEmpty()) {
            return null
        }
        return try {
            val json = JSONObject(raw)
            StoredTlsMetadata(
                version = json.optInt("version", 0),
                serverId = json.optString("serverId", ""),
                hostLabel = json.optString("hostLabel", ""),
                localIp = json.optString("localIp", ""),
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun saveMetadata(
        metadataFile: File,
        metadata: StoredTlsMetadata,
    ) {
        val json =
            JSONObject()
                .put("version", metadata.version)
                .put("serverId", metadata.serverId)
                .put("hostLabel", metadata.hostLabel)
                .put("localIp", metadata.localIp)
        metadataFile.writeText(json.toString())
    }

    private fun notBefore(): Date = Date(System.currentTimeMillis() - TimeUnit.MINUTES.toMillis(5))

    private fun notAfter(validityDays: Long): Date =
        Date(System.currentTimeMillis() + TimeUnit.DAYS.toMillis(validityDays))

    private fun nextSerialNumber(): BigInteger {
        var serial = BigInteger(128, SECURE_RANDOM)
        while (serial == BigInteger.ZERO) {
            serial = BigInteger(128, SECURE_RANDOM)
        }
        return serial
    }
}

private data class RootMaterial(
    val certificate: X509Certificate,
    val keyPair: KeyPair,
    val certificatePem: String,
    val privateKeyPem: String,
)

private data class LeafMaterial(
    val certificatePem: String,
    val privateKeyPem: String,
)

private data class StoredTlsMetadata(
    val version: Int,
    val serverId: String,
    val hostLabel: String,
    val localIp: String,
)
