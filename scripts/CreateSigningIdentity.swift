import Foundation
import Security

// The private key is generated persistently in the keychain and is never exported.
// Minimal DER certificate construction avoids storing PEM/P12 material on disk.
typealias Bytes = [UInt8]
func der(_ tag: UInt8, _ value: Bytes) -> Bytes {
    let length: Bytes
    if value.count < 128 { length = [UInt8(value.count)] }
    else {
        var count = value.count; var bytes: Bytes = []
        while count > 0 { bytes.insert(UInt8(count & 255), at: 0); count >>= 8 }
        length = [0x80 | UInt8(bytes.count)] + bytes
    }
    return [tag] + length + value
}
func sequence(_ value: Bytes) -> Bytes { der(0x30, value) }
func oid(_ value: Bytes) -> Bytes { der(0x06, value) }
func name(_ text: String) -> Bytes {
    sequence(der(0x31, sequence(oid([0x55,0x04,0x03]) + der(0x0c, Array(text.utf8)))))
}
enum Failure: Error { case key, publicKey, signature, certificate, keychain(OSStatus) }
let label = "UltraCorrect Self-Signed"
let tag = Data("local.ultracorrect.signing.v2".utf8)
var error: Unmanaged<CFError>?
let attributes: [CFString: Any] = [
    kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048,
    kSecPrivateKeyAttrs: [kSecAttrIsPermanent: true, kSecAttrApplicationTag: tag, kSecAttrLabel: label]
]
var stored: CFTypeRef?
let lookup = SecItemCopyMatching([kSecClass: kSecClassKey, kSecAttrApplicationTag: tag,
                                  kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecReturnRef: true] as CFDictionary, &stored)
let key: SecKey
if lookup == errSecSuccess, let stored { key = (stored as! SecKey) }
else if let created = SecKeyCreateRandomKey(attributes as CFDictionary, &error) { key = created }
else { throw Failure.key }
guard let publicKey = SecKeyCopyPublicKey(key),
      let publicData = SecKeyCopyExternalRepresentation(publicKey, &error) else { throw Failure.publicKey }
let signatureAlgorithm = sequence(oid([0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x0b]) + [0x05,0])
let rsaAlgorithm = sequence(oid([0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01]) + [0x05,0])
let formatter = DateFormatter()
formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
formatter.dateFormat = "yyyyMMddHHmmss'Z'"
let now = Date(); let end = Calendar(identifier: .gregorian).date(byAdding: .year, value: 10, to: now)!
let validity = sequence(der(0x18, Array(formatter.string(from: now.addingTimeInterval(-300)).utf8)) +
                        der(0x18, Array(formatter.string(from: end).utf8)))
var serial = Bytes(repeating: 0, count: 16)
guard SecRandomCopyBytes(kSecRandomDefault, serial.count, &serial) == errSecSuccess else { throw Failure.key }
serial[0] = (serial[0] & 0x7f) | 1
let basicConstraints = sequence(oid([0x55,0x1d,0x13]) + [0x01,0x01,0xff] + der(0x04, sequence([])))
let keyUsage = sequence(oid([0x55,0x1d,0x0f]) + [0x01,0x01,0xff] + der(0x04, der(0x03, [7,0x80])))
let codeSigning = sequence(oid([0x55,0x1d,0x25]) + der(0x04, sequence(oid([0x2b,6,1,5,5,7,3,3]))))
let body = sequence(der(0xa0, [0x02,1,2]) + der(0x02, serial) + signatureAlgorithm + name(label) + validity + name(label) +
                    sequence(rsaAlgorithm + der(0x03, [0] + Array(publicData as Data))) +
                    der(0xa3, sequence(basicConstraints + keyUsage + codeSigning)))
guard let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(body) as CFData, &error) else { throw Failure.signature }
let certificateData = Data(sequence(body + signatureAlgorithm + der(0x03, [0] + Array(signature as Data))))
guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else { throw Failure.certificate }
let status = SecItemAdd([kSecClass: kSecClassCertificate, kSecValueRef: certificate] as CFDictionary, nil)
guard status == errSecSuccess || status == errSecDuplicateItem else { throw Failure.keychain(status) }
guard let policy = SecPolicyCreateWithProperties(kSecPolicyAppleCodeSigning, nil) else { throw Failure.certificate }
let trust: [String: Any] = [kSecTrustSettingsPolicy: policy,
                              kSecTrustSettingsResult: SecTrustSettingsResult.trustRoot.rawValue]
let trustStatus = SecTrustSettingsSetTrustSettings(certificate, .user, [trust] as CFArray)
guard trustStatus == errSecSuccess else { throw Failure.keychain(trustStatus) }
print("Identity created. The private key remains in the login keychain.")
