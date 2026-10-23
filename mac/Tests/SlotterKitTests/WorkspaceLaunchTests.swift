import Testing
import Foundation
import Dispatch
@testable import SlotterKit

private let launchDisplay = DisplayInfo(id: 1, uuid: "launch-screen", name: "Launch screen",
    frameAX: CGRect(x: 0, y: 0, width: 1280, height: 800),
    workAreaAX: CGRect(x: 0, y: 30, width: 1280, height: 770),
    pointSize: CGSize(width: 1280, height: 800), pixelSize: CGSize(width: 1280, height: 800),
    isPrimary: true, duplicateIndex: 0)

@Test @MainActor func cancellingLaunchWhileWaitingForAWindowStopsRemainingPrograms() async throws {
    let launcher = WorkspaceLauncher()
    let monitor = MonitorRef(ordinal: 1, uuid: launchDisplay.uuid)
    let workspace = Workspace(name: "Cancellation", zones: [
        Zone(monitor: monitor, x: 0, y: 0, w: 50, h: 100, program: "Probe"),
        Zone(monitor: monitor, x: 50, y: 0, w: 50, h: 100, program: "Probe")
    ])
    let task = Task {
        await launcher.activate(workspace, programs: [Program(name: "Probe", path: "/usr/bin/false")],
            snapshot: DisplaySnapshot(displays: [launchDisplay], flipY: 800))
    }
    try await Task.sleep(for: .milliseconds(200))
    task.cancel()
    let result = await task.value
    #expect(result?.planned == 1)
    #expect(result?.placed == 0)
    #expect(!launcher.isLaunching)
}

@Test @MainActor func cancelledQueuedAXWorkDoesNotRunItsMutation() async throws {
    AX.queue.async { Thread.sleep(forTimeInterval: 0.2) }
    let task = Task { await AX.perform(cancelledValue: false) { true } }
    try await Task.sleep(for: .milliseconds(50))
    task.cancel()
    let mutationRan = await task.value
    #expect(!mutationRan)
}
