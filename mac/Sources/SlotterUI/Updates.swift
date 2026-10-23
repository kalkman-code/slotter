import AppKit
import Foundation
import SlotterKit
import Sparkle

enum UpdateSelection {
    // Sparkle passes an appcast already filtered for OS requirements, channels and skipped versions.
    static func bestMacUpdate(in items: [SUAppcastItem]) -> SUAppcastItem? {
        items.filter(\.isMacOsUpdate).max {
            SUStandardVersionComparator.default.compareVersion($0.versionString, toVersion: $1.versionString) == .orderedAscending
        }
    }
}

@MainActor
public final class UpdateController: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!
    private var observation: NSKeyValueObservation?
    private var started = false
    public var onChange: (() -> Void)?
    public private(set) var canCheck = false

    public override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    }

    static func feedURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                        info: [String: Any]? = Bundle.main.infoDictionary) -> URL? {
        guard let value = environment["SLOTTER_FEED_URL"] ?? info?["SUFeedURL"] as? String,
              let url = URL(string: value), let host = url.host, url.user == nil, url.password == nil else { return nil }
        let loopback = ["127.0.0.1", "localhost", "[::1]", "::1"].contains(host.lowercased())
        guard url.scheme?.lowercased() == "https" || (url.scheme?.lowercased() == "http" && loopback) else { return nil }
        return url
    }

    public var automaticallyChecks: Bool {
        get { started && controller.updater.automaticallyChecksForUpdates }
        set {
            guard started else { return }
            controller.updater.automaticallyChecksForUpdates = newValue
            onChange?()
        }
    }

    public func start() {
        guard !started, Self.feedURL() != nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            Log.error("updates: invalid feed URL or public key; updater not started")
            return
        }
        started = true
        controller.startUpdater()
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheck = updater.canCheckForUpdates
                self?.onChange?()
            }
        }
    }

    public func checkNow() {
        guard canCheck else { return }
        controller.checkForUpdates(nil)
    }

    public func feedURLString(for updater: SPUUpdater) -> String? { Self.feedURL()?.absoluteString }

    public func bestValidUpdate(in appcast: SUAppcast, for updater: SPUUpdater) -> SUAppcastItem? {
        UpdateSelection.bestMacUpdate(in: appcast.items) ?? SUAppcastItem.empty()
    }

    public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Log.write("updates: found \(item.displayVersionString) (build \(item.versionString))")
    }

    public func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Log.error("updates: \(error.localizedDescription)")
    }

    public func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                          forUpdate update: SUAppcastItem,
                                                          state: SPUUserUpdateState) {
        if handleShowingUpdate { NSApp.activate() }
    }
}
