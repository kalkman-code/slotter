import Foundation

public struct IniDocument {
    private enum Line {
        case other(String)
        case section(name: String, raw: String)
        case pair(key: String, value: String, raw: String)
    }

    private var lines: [Line] = []

    public init() {}

    public init(text: String) {
        for raw in text.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") , trimmed.hasSuffix("]"), trimmed.count > 2 {
                let name = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                lines.append(.section(name: name, raw: raw))
            } else if trimmed.hasPrefix(";") || trimmed.hasPrefix("#") || trimmed.isEmpty {
                lines.append(.other(raw))
            } else if let separator = raw.firstIndex(of: "=") {
                let key = String(raw[raw.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
                let value = String(raw[raw.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                lines.append(.pair(key: key, value: value, raw: raw))
            } else {
                lines.append(.other(raw))
            }
        }
        if case .other(let last) = lines.last, last.isEmpty { lines.removeLast() }
    }

    public var sectionNames: [String] {
        lines.compactMap { if case .section(let name, _) = $0 { return name } else { return nil } }
    }

    public func hasSection(_ name: String) -> Bool { range(of: name) != nil }

    public func string(_ section: String, _ key: String, default fallback: String = "") -> String {
        guard let range = range(of: section) else { return fallback }
        for index in range {
            if case .pair(let existing, let value, _) = lines[index],
               existing.caseInsensitiveCompare(key) == .orderedSame {
                return value
            }
        }
        return fallback
    }

    public func int(_ section: String, _ key: String, default fallback: Int = 0) -> Int {
        Int(string(section, key)) ?? fallback
    }

    public func bool(_ section: String, _ key: String, default fallback: Bool = false) -> Bool {
        let raw = string(section, key).lowercased()
        if raw.isEmpty { return fallback }
        return raw == "1" || raw == "true" || raw == "yes"
    }

    public func pairs(in section: String) -> [(key: String, value: String)] {
        guard let range = range(of: section) else { return [] }
        return range.compactMap { index in
            if case .pair(let key, let value, _) = lines[index] { return (key, value) }
            return nil
        }
    }

    public mutating func set(_ section: String, _ key: String, _ value: String?) {
        guard let range = range(of: section) else {
            guard let value else { return }
            if !lines.isEmpty { lines.append(.other("")) }
            lines.append(.section(name: section, raw: "[\(section)]"))
            lines.append(.pair(key: key, value: value, raw: "\(key)=\(value)"))
            return
        }

        for index in range {
            if case .pair(let existing, _, _) = lines[index],
               existing.caseInsensitiveCompare(key) == .orderedSame {
                if let value {
                    lines[index] = .pair(key: existing, value: value, raw: "\(existing)=\(value)")
                } else {
                    lines.remove(at: index)
                }
                return
            }
        }

        guard let value else { return }
        lines.insert(.pair(key: key, value: value, raw: "\(key)=\(value)"), at: insertionPoint(for: range))
    }

    public mutating func replaceSection(_ section: String,
                                        removingKeysMatching predicate: (String) -> Bool,
                                        with newPairs: [(key: String, value: String)]) {
        guard let range = range(of: section) else {
            if !lines.isEmpty { lines.append(.other("")) }
            lines.append(.section(name: section, raw: "[\(section)]"))
            lines.append(contentsOf: newPairs.map { .pair(key: $0.key, value: $0.value, raw: "\($0.key)=\($0.value)") })
            return
        }

        var doomed: [Int] = []
        for index in range {
            if case .pair(let key, _, _) = lines[index], predicate(key) { doomed.append(index) }
        }

        let anchor = doomed.first ?? insertionPoint(for: range)
        for index in doomed.reversed() { lines.remove(at: index) }
        lines.insert(contentsOf: newPairs.map { .pair(key: $0.key, value: $0.value, raw: "\($0.key)=\($0.value)") },
                     at: min(anchor, lines.count))
    }

    public mutating func removeSection(_ section: String) {
        guard let range = range(of: section), let header = headerIndex(of: section) else { return }
        for index in range.reversed() { lines.remove(at: index) }
        lines.remove(at: header)
    }

    public mutating func renameSection(_ section: String, to newName: String) {
        guard let header = headerIndex(of: section) else { return }
        lines[header] = .section(name: newName, raw: "[\(newName)]")
    }

    public func serialized() -> String {
        lines.map { line in
            switch line {
            case .other(let raw): return raw
            case .section(_, let raw): return raw
            case .pair(_, _, let raw): return raw
            }
        }.joined(separator: "\n") + "\n"
    }

    private func headerIndex(of section: String) -> Int? {
        lines.firstIndex { line in
            if case .section(let name, _) = line { return name.caseInsensitiveCompare(section) == .orderedSame }
            return false
        }
    }

    private func range(of section: String) -> Range<Int>? {
        guard let header = headerIndex(of: section) else { return nil }
        var end = header + 1
        while end < lines.count {
            if case .section = lines[end] { break }
            end += 1
        }
        return (header + 1)..<end
    }

    private func insertionPoint(for range: Range<Int>) -> Int {
        var index = range.upperBound
        while index > range.lowerBound {
            if case .other(let raw) = lines[index - 1], raw.trimmingCharacters(in: .whitespaces).isEmpty {
                index -= 1
            } else {
                break
            }
        }
        return index
    }
}
