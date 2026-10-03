import Foundation
import Security
import CommonCrypto

public struct TLSCertificateInfo {
    public let subject: String
    public let fingerprintSHA256: String
    public let notBefore: Date
    public let notAfter: Date
    public let coveredIPs: [String]
    public let isTrustedByThisMac: Bool
}

public final class TLSCertificateManager {
    public static let shared = TLSCertificateManager()

    private let label = "com.dropit.local.tls"
    private let coveredIPsKey = "com.dropit.tls.coveredIPs"
    private var applicationTag: Data { Data(label.utf8) }
    private let commonName = "Dropit Local CA"
    private let organization = "Dropit"
    private let organizationalUnit = "Local Network Transfer"
    private let dnsName = "dropit.local"

    private static let day: TimeInterval = 60 * 60 * 24
    private static let oidCommonName = "2.5.4.3"
    private static let oidOrganization = "2.5.4.10"
    private static let oidOrganizationalUnit = "2.5.4.11"
    private static let oidSignatureAlgorithm = "1.2.840.113549.1.1.11"

    private var cachedIdentity: SecIdentity?
    private var cachedCoveredIPs: Set<String> = []

    private init() {}

    // MARK: - Identity

    public func identity(covering ips: [String]) -> SecIdentity? {
        let wanted = Set(ips)
        if let cached = cachedIdentity, cachedCoveredIPs.isSuperset(of: wanted) {
            return cached
        }
        guard createOrLoadPrivateKey() != nil else { return nil }

        let storedCoveredIPs = recordedCoveredIPs()
        if storedCoveredIPs.isSuperset(of: wanted),
           let storedData = storedCertificateData(),
           let stored = loadIdentity(matchingCertificateData: storedData) {
            cachedIdentity = stored
            cachedCoveredIPs = storedCoveredIPs
            return stored
        }
        guard let created = buildIdentity(ipAddresses: ips) else { return nil }
        cachedIdentity = created
        cachedCoveredIPs = Set(ips)
        return created
    }

    private func recordedCoveredIPs() -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: coveredIPsKey) ?? ""
        return Set(raw.split(separator: ",").map(String.init))
    }

    private func recordCoveredIPs(_ ips: [String]) {
        UserDefaults.standard.set(ips.sorted().joined(separator: ","), forKey: coveredIPsKey)
    }

    public func invalidateCache() {
        cachedIdentity = nil
        cachedCoveredIPs = []
    }

    @discardableResult
    public func deleteStoredMaterial() -> Bool {
        invalidateCache()
        deleteStoredCertificates()
        let keyStatus = SecItemDelete([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: applicationTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA
        ] as CFDictionary)
        return keyStatus == errSecSuccess
    }

    // MARK: - Certificate data

    public func certificateData(covering ips: [String]) -> Data? {
        guard let identity = identity(covering: ips), let cert = certificate(for: identity) else { return nil }
        return SecCertificateCopyData(cert) as Data
    }

    public func info(covering ips: [String]) -> TLSCertificateInfo? {
        guard let identity = identity(covering: ips), let cert = certificate(for: identity) else { return nil }
        let der = SecCertificateCopyData(cert) as Data
        let validity = DERReader.certificateValidity(der)
        return TLSCertificateInfo(
            subject: SecCertificateCopySubjectSummary(cert) as String? ?? commonName,
            fingerprintSHA256: sha256Hex(der),
            notBefore: validity?.notBefore ?? Date(),
            notAfter: validity?.notAfter ?? Date(),
            coveredIPs: ips,
            isTrustedByThisMac: isTrustedByThisMac()
        )
    }

    private func certificate(for identity: SecIdentity?) -> SecCertificate? {
        guard let identity = identity else { return nil }
        var cert: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess else { return nil }
        return cert
    }

    private func isTrustedByThisMac() -> Bool {
        guard let der = certificateData(covering: []),
              let cert = SecCertificateCreateWithData(nil, der as CFData) else { return false }
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(cert, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
              let trust = trust else { return false }
        var error: CFError?
        return SecTrustEvaluateWithError(trust, &error)
    }

    // MARK: - Keychain

    /// Finds the identity that pairs our certificate with the stored private key.
    ///
    /// `kSecClassIdentity` ignores label attributes as search keys, so a constrained
    /// query silently degenerates into "any identity" and can hand back an unrelated
    /// certificate. We therefore enumerate identities and compare certificate bytes.
    /// Only certificate data is inspected: touching foreign private keys can trigger a
    /// keychain authorisation prompt and block headless processes.
    private func loadIdentity(matchingCertificateData expected: Data) -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var item: CFTypeRef?
        let st = SecItemCopyMatching(query as CFDictionary, &item)
        guard st == errSecSuccess,
              let identities = item as? [SecIdentity] else { return nil }
        for identity in identities {
            var cert: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess,
                  let certificate = cert,
                  SecCertificateCopyData(certificate) as Data == expected else { continue }
            return identity
        }
        return nil
    }

    /// DER of the certificate currently held in the keychain, if any.
    private func storedCertificateData() -> Data? {
        var item: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let certificates = item as? [SecCertificate] else { return nil }
        for certificate in certificates {
            guard (SecCertificateCopySubjectSummary(certificate) as String? ?? "") == commonName else { continue }
            return SecCertificateCopyData(certificate) as Data
        }
        return nil
    }

    private func privateKeyFromKeychain() -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: applicationTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return (item as! SecKey?)
    }

    private func createOrLoadPrivateKey() -> SecKey? {
        if let existing = privateKeyFromKeychain() { return existing }

        var privateAttrs: [String: Any] = [
            kSecAttrIsPermanent as String: true,
            kSecAttrApplicationTag as String: applicationTag,
            kSecAttrLabel as String: commonName
        ]

        // The app is ad-hoc signed and re-signed on every build. Without an access
        // object that trusts every application, keychain items created by a previous
        // build would trigger an authorisation prompt (and block headless runs) the
        // next time the key is used for signing. SecAccessCreate is deprecated but is
        // still the only way to set this on the legacy keychain.
        var access: SecAccess?
        let created = SecAccessCreate(commonName as CFString, [] as CFArray, &access)
        if created == errSecSuccess, let access = access {
            privateAttrs[kSecAttrAccess as String] = access
        }

        let params: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: privateAttrs
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(params as CFDictionary, &error) else {
            let message = error?.takeRetainedValue().localizedDescription ?? "unknown"
            NSLog("Dropit: failed to create TLS key: \(message)")
            return nil
        }
        return key
    }

    private func storeCertificate(_ der: Data) {
        deleteStoredCertificates()

        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            NSLog("Dropit: cannot store TLS certificate, failed to parse")
            return
        }
        let status = SecItemAdd([
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate
        ] as CFDictionary, nil)
        if status != errSecSuccess {
            NSLog("Dropit: failed to store TLS certificate (OSStatus \(status))")
        }
    }

    /// Certificate items derive their keychain label from the subject common name, so
    /// they cannot be targeted with kSecAttrLabel. We locate ours by subject summary and
    /// remove them by value reference.
    private func deleteStoredCertificates() {
        var item: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let certificates = item as? [SecCertificate] else { return }
        for certificate in certificates {
            let subject = SecCertificateCopySubjectSummary(certificate) as String? ?? ""
            guard subject == commonName else { continue }
            SecItemDelete([
                kSecClass as String: kSecClassCertificate,
                kSecValueRef as String: certificate
            ] as CFDictionary)
        }
    }

    // MARK: - Certificate construction

    private func buildIdentity(ipAddresses: [String]) -> SecIdentity? {
        guard let privateKey = createOrLoadPrivateKey(),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let pkcs1 = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? else {
            NSLog("Dropit: unable to obtain TLS key pair")
            return nil
        }

        guard let der = makeCertificateDER(privateKey: privateKey, pkcs1PublicKey: pkcs1, ipAddresses: ipAddresses) else {
            return nil
        }

        guard SecCertificateCreateWithData(nil, der as CFData) != nil else {
            NSLog("Dropit: generated certificate failed to parse")
            return nil
        }

        storeCertificate(der)
        recordCoveredIPs(ipAddresses)

        guard let identity = loadIdentity(matchingCertificateData: der) else {
            NSLog("Dropit: certificate stored but no SecIdentity could be resolved")
            return nil
        }
        return identity
    }

    private func makeCertificateDER(privateKey: SecKey, pkcs1PublicKey: Data, ipAddresses: [String]) -> Data? {
        let notBefore = Date().addingTimeInterval(-Self.day)
        let notAfter = Date().addingTimeInterval(Self.day * 3650)

        var serialBytes = Data((0..<8).map { _ in UInt8.random(in: 0...255) })
        if let first = serialBytes.first, first & 0x80 != 0 { serialBytes.insert(0x00, at: 0) }
        let serialValue = Int(serialBytes.reduce(UInt64(0)) { partial, byte in
            partial &<< 8 | UInt64(byte)
        } >> 1)

        let distinguishedName: [(String, String)] = [
            (Self.oidCommonName, commonName),
            (Self.oidOrganization, organization),
            (Self.oidOrganizationalUnit, organizationalUnit)
        ]

        let extensions: [Data] = [
            DER.x509Extension(
                oid: "2.5.29.17",
                critical: false,
                value: DER.subjectAltName(dnsNames: [dnsName], ipAddresses: ipAddresses)
            ),
            DER.x509Extension(
                oid: "2.5.29.19",
                critical: true,
                value: DER.basicConstraints(isCA: true, pathLen: 0)
            ),
            DER.x509Extension(
                oid: "2.5.29.37",
                critical: false,
                value: DER.extendedKeyUsage(["1.3.6.1.5.5.7.3.1", "1.3.6.1.5.5.7.3.2"])
            ),
            DER.x509Extension(
                oid: "2.5.29.15",
                critical: true,
                value: DER.keyUsage([0xA6, 0x00])
            ),
            DER.x509Extension(
                oid: "2.5.29.14",
                critical: false,
                value: DER.octetString(sha256Data(pkcs1PublicKey))
            )
        ]

        let tbsCertificate = DER.sequence([
            DER.contextSpecific(0, DER.integer(2)),
            DER.integer(serialValue),
            DER.algorithmIdentifier(Self.oidSignatureAlgorithm),
            DER.rdnSequence(distinguishedName),
            DER.sequence([DER.time(notBefore), DER.time(notAfter)]),
            DER.rdnSequence(distinguishedName),
            DER.subjectPublicKeyInfo(pkcs1PublicKey: pkcs1PublicKey),
            DER.contextSpecific(3, DER.sequence(extensions))
        ])

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            tbsCertificate as CFData,
            &error
        ) as Data? else {
            let message = error?.takeRetainedValue().localizedDescription ?? "unknown"
            NSLog("Dropit: failed to sign certificate: \(message)")
            return nil
        }

        let certificate = DER.sequence([
            tbsCertificate,
            DER.algorithmIdentifier(Self.oidSignatureAlgorithm),
            DER.bitString(signature, unusedBits: 0)
        ])

        return certificate
    }

    // MARK: - Utilities

    private func sha256Data(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { raw in
            _ = CC_SHA256(raw.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest)
    }

    private func sha256Hex(_ data: Data) -> String {
        return sha256Data(data).map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}
