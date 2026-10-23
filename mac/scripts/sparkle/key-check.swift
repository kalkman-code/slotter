import CryptoKit
import Foundation

func fail() -> Never {
    FileHandle.standardError.write(Data("key-check: invalid key or public key mismatch; nothing signed\n".utf8))
    exit(1)
}
guard CommandLine.arguments.count == 2,
      let expected = Data(base64Encoded: CommandLine.arguments[1]), expected.count == 32,
      let line = readLine(), let secret = Data(base64Encoded: line.trimmingCharacters(in: .whitespacesAndNewlines)) else { fail() }
let publicKey: Data
switch secret.count {
case 32:
    guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: secret) else { fail() }
    publicKey = key.publicKey.rawRepresentation
case 96:
    publicKey = secret.suffix(32)
default: fail()
}
guard publicKey == expected else { fail() }
print("key-check: matches expected public key")
