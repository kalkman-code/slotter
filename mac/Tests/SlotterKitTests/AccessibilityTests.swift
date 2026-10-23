import ApplicationServices
import Foundation
import Testing
@testable import SlotterKit

@Test @MainActor func workerHitTestRunsOnMainThread() async {
    let point = CGPoint(x: 123, y: 456)
    let result = await AX.perform {
        #expect(!Thread.isMainThread)
        return AX.element(at: point) { _, x, y, found in
            #expect(Thread.isMainThread)
            #expect(x == 123)
            #expect(y == 456)
            found.pointee = AXUIElementCreateApplication(getpid())
            return .success
        }
    }
    #expect(result != nil)
    #expect(result.flatMap { AX.pid(of: $0) } == getpid())
}

@Test @MainActor func mainThreadHitTestReturnsWithoutRedispatching() {
    let result = AX.element(at: .zero) { _, _, _, found in
        #expect(Thread.isMainThread)
        found.pointee = AXUIElementCreateApplication(getpid())
        return .success
    }
    #expect(result != nil)
}

@Test @MainActor func failedWorkerHitTestReturnsNoElement() async {
    let result = await AX.perform {
        AX.element(at: .zero) { _, _, _, found in
            #expect(Thread.isMainThread)
            found.pointee = AXUIElementCreateApplication(getpid())
            return .cannotComplete
        }
    }
    #expect(result == nil)
}
