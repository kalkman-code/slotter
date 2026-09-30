import Testing
import Foundation
@testable import SnappyKit

@Test func logDirectoryIsUnderUserLibrary() {
    #expect(Log.fileURL.path.hasSuffix("Library/Logs/Snappy/snappy.log"))
}
