import CryptoKit
import Foundation

func require(_ condition: Bool, _ message: String) {
    guard condition else {
        FileHandle.standardError.write(Data("FAIL \(message)\n".utf8))
        exit(1)
    }
    print("ok \(message)")
}
let args = CommandLine.arguments
guard args.count == 5, let publicData = Data(base64Encoded: args[2]),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: publicData) else { exit(2) }
let data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
let marker = Data("<!-- sparkle-signatures:\n".utf8)
guard let start = data.range(of: marker, options: .backwards),
      let end = data.range(of: Data("-->".utf8), in: start.upperBound..<data.endIndex) else { require(false, "feed signing block"); exit(1) }
let content = data.subdata(in: data.startIndex..<start.lowerBound)
let fields = String(decoding: data.subdata(in: start.upperBound..<end.lowerBound), as: UTF8.self).split(separator: "\n")
func field(_ name: String) -> String? { fields.first { $0.hasPrefix(name) }.map { $0.dropFirst(name.count).trimmingCharacters(in: .whitespaces) } }
require(field("length:").flatMap(Int.init) == content.count, "feed signed length")
require(field("edSignature:").flatMap { Data(base64Encoded: $0) }.map { publicKey.isValidSignature($0, for: content) } == true, "feed EdDSA signature")
let doc = try XMLDocument(data: content)
var identities = Set<String>()
let items = try doc.nodes(forXPath: "//channel/item").compactMap { $0 as? XMLElement }
require(!items.isEmpty, "feed has items")
for item in items {
    guard let enclosure = item.elements(forName: "enclosure").first,
          let urlString = enclosure.attribute(forName: "url")?.stringValue,
          let url = URL(string: urlString),
          let length = enclosure.attribute(forName: "length")?.stringValue.flatMap(Int.init),
          let version = item.elements(forName: "sparkle:shortVersionString").first?.stringValue,
          let build = item.elements(forName: "sparkle:version").first?.stringValue, Int(build) != nil else {
        require(false, "item metadata"); exit(1)
    }
    let os = enclosure.attribute(forName: "sparkle:os")?.stringValue ?? "macos"
    require(os == "macos" || os == "windows", "known platform \(os)")
    require(identities.insert("\(build)-\(os)").inserted, "unique build/platform \(build)-\(os)")
    let asset = os == "macos" ? "Slotter-\(version).dmg" : "Slotter-\(version)-win-x64.zip"
    require(urlString == args[4].replacingOccurrences(of: "{version}", with: version) + asset, "\(os) \(version) download URL")
    let archive = URL(fileURLWithPath: args[3], isDirectory: true).appendingPathComponent(url.lastPathComponent)
    guard let bytes = try? Data(contentsOf: archive) else { print("skip earlier archive \(asset): not supplied"); continue }
    require(bytes.count == length, "\(os) archive length")
    if os == "macos" {
        require(item.elements(forName: "sparkle:minimumSystemVersion").first?.stringValue == "14.0", "minimum macOS 14.0")
        require(enclosure.attribute(forName: "sparkle:edSignature")?.stringValue.flatMap { Data(base64Encoded: $0) }.map { publicKey.isValidSignature($0, for: bytes) } == true, "macOS archive EdDSA signature")
    } else {
        let sha = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        require(enclosure.attribute(forName: "slotter:sha256")?.stringValue == sha, "Windows SHA-256")
    }
}
print("verify-appcast: all checks passed")
