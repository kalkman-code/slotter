import Testing
import Foundation
@testable import SlotterKit

@Test func logDirectoryIsUnderUserLibrary() {
    #expect(Log.fileURL.path.hasSuffix("Library/Logs/Slotter/slotter.log"))
}

@Test func minimumWindowSizeKeepsItsRealExtentInsideTheDisplay() {
    let work = CGRect(x: 0, y: 33, width: 1728, height: 1084)
    let right = CGRect(x: 864, y: 33, width: 864, height: 1084)
    #expect(Geo.windowOrigin(right.origin, actualSize: CGSize(width: 900, height: 1084), zone: right, workArea: work) == CGPoint(x: 828, y: 33))
    #expect(Geo.windowOrigin(right.origin, actualSize: right.size, zone: right, workArea: work) == right.origin)
    let negative = CGRect(x: -1728, y: 33, width: 1728, height: 1084)
    let left = CGRect(x: -1728, y: 33, width: 864, height: 1084)
    #expect(Geo.windowOrigin(left.origin, actualSize: CGSize(width: 1800, height: 1200), zone: left, workArea: negative) == left.origin)
}
