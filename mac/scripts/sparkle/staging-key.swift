// A separate Keychain account holds the disposable test seed; the seed never reaches stdout or disk.
import CryptoKit
import Foundation
import Security
import LocalAuthentication

let args = CommandLine.arguments
guard args.count >= 3, args[2].hasPrefix("slotter-staging-") else { exit(2) }
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "uk.co.kalkman.slotter.staging",
    kSecAttrAccount as String: args[2],
]
func fail(_ status: OSStatus) -> Never {
    FileHandle.standardError.write(Data("Staging Keychain operation failed (\(status))\n".utf8))
    exit(1)
}
switch args[1] {
case "create":
    let key = Curve25519.Signing.PrivateKey()
    var attributes = query
    attributes[kSecValueData as String] = key.rawRepresentation
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let result = SecItemAdd(attributes as CFDictionary, nil)
    guard result == errSecSuccess else { fail(result) }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "run":
    guard args.count >= 4 else { exit(2) }
    var readQuery = query
    readQuery[kSecReturnData as String] = true
    let context = LAContext()
    context.interactionNotAllowed = true
    readQuery[kSecUseAuthenticationContext as String] = context
    var value: CFTypeRef?
    let result = SecItemCopyMatching(readQuery as CFDictionary, &value)
    guard result == errSecSuccess, let secret = value as? Data else { fail(result) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: args[3])
    process.arguments = Array(args.dropFirst(4))
    var environment = ProcessInfo.processInfo.environment
    environment["SPARKLE_ED_KEY"] = secret.base64EncodedString()
    process.environment = environment
    try process.run()
    process.waitUntilExit()
    exit(process.terminationStatus)
case "delete":
    let result = SecItemDelete(query as CFDictionary)
    guard result == errSecSuccess || result == errSecItemNotFound else { fail(result) }
default: exit(2)
}
