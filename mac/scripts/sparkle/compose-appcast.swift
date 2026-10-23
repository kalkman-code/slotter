import CryptoKit
import Foundation

let sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
let slotter = "https://kalkmancode.co.uk/slotter/appcast"
let args = CommandLine.arguments
guard args.count == 10 else { fatalError("Expected output, previous feed, version, build, DMG, signature, Windows zip, notes and URL template") }
let output = args[1], previous = args[2], version = args[3], build = args[4]
let dmg = URL(fileURLWithPath: args[5]), windows = URL(fileURLWithPath: args[7])
let prefix = args[9].replacingOccurrences(of: "{version}", with: version)
let document = try XMLDocument(xmlString: "<?xml version=\"1.0\" encoding=\"utf-8\"?><rss version=\"2.0\" xmlns:sparkle=\"\(sparkle)\" xmlns:slotter=\"\(slotter)\"><channel><title>Slotter updates</title><link>https://kalkmancode.co.uk/slotter/</link><description>Slotter updates for macOS and Windows</description><language>en-GB</language></channel></rss>")
let channel = document.rootElement()!.elements(forName: "channel")[0]
let notes = try String(contentsOfFile: args[8], encoding: .utf8)
guard !notes.isEmpty, !notes.lowercased().contains("<script"), !notes.lowercased().contains("src=\"http"), !notes.lowercased().contains("src='http") else { fatalError("Release notes must be embedded and contain no scripts or remote resources") }
func element(_ name: String, _ text: String) -> XMLElement { XMLElement(name: name, stringValue: text) }
func attribute(_ name: String, _ value: String) -> XMLNode { XMLNode.attribute(withName: name, stringValue: value) as! XMLNode }
for (platform, archive) in [("macos", dmg), ("windows", windows)] {
    let data = try Data(contentsOf: archive)
    let item = XMLElement(name: "item")
    item.addChild(element("title", "Slotter \(version) (\(platform == "macos" ? "macOS" : "Windows"))"))
    item.addChild(element("sparkle:version", build))
    item.addChild(element("sparkle:shortVersionString", version))
    if platform == "macos" { item.addChild(element("sparkle:minimumSystemVersion", "14.0")) }
    item.addChild(element("description", notes))
    let enclosure = XMLElement(name: "enclosure")
    enclosure.addAttribute(attribute("url", prefix + archive.lastPathComponent))
    enclosure.addAttribute(attribute("length", String(data.count)))
    enclosure.addAttribute(attribute("type", "application/octet-stream"))
    enclosure.addAttribute(attribute("sparkle:os", platform))
    if platform == "macos" {
        enclosure.addAttribute(attribute("sparkle:edSignature", args[6]))
    } else {
        enclosure.addAttribute(attribute("slotter:sha256", SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()))
    }
    item.addChild(enclosure)
    channel.addChild(item)
}
if !previous.isEmpty {
    let oldDocument = try XMLDocument(contentsOf: URL(fileURLWithPath: previous))
    for case let item as XMLElement in try oldDocument.nodes(forXPath: "//channel/item") {
        // Re-running one release replaces only that release's two items; older download URLs survive.
        if item.elements(forName: "sparkle:version").first?.stringValue != build {
            channel.addChild(item.copy() as! XMLElement)
        }
    }
}
try document.xmlData(options: [.nodePrettyPrint]).write(to: URL(fileURLWithPath: output))
