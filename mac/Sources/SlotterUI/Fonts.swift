import CoreText
import Foundation
import SlotterKit

public enum Fonts {
    /// `build.sh` copies `fonts/` into `Contents/Resources/Fonts`. `SLOTTER_FONTS_DIR` points
    /// anything run outside the bundle (`swift run`, a render harness) at the repo's `fonts/`.
    public static func register() {
        let directory = ProcessInfo.processInfo.environment["SLOTTER_FONTS_DIR"].map { URL(fileURLWithPath: $0) }
            ?? Bundle.main.resourceURL?.appending(path: "Fonts")
        guard let directory else { return }
        for file in T.fontFiles {
            let url = directory.appending(path: file)
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                Log.error("font not registered: \(file)")
            }
        }
    }
}
