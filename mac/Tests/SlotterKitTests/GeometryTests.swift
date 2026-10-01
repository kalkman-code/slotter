import Testing
import Foundation
@testable import SlotterKit

@Test func logDirectoryIsUnderUserLibrary() {
    #expect(Log.fileURL.path.hasSuffix("Library/Logs/Slotter/slotter.log"))
}
