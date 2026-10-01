//
//  JournalImportModels.swift
//  OffRecord
//
//  Shared vocabulary for importing entries from other journal apps: where the
//  files come from, what one imported entry looks like before it is saved,
//  and what was skipped and why.
//

import CryptoKit
import Foundation
import UniformTypeIdentifiers

enum JournalImportFormat: String, CaseIterable, Identifiable, Sendable {
    case dayOne
    case appleJournal
    case markdown
    case csv

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dayOne: return String(localized: "Day One", comment: "Import source: the Day One journal app. Product name.")
        case .appleJournal: return String(localized: "Apple Journal", comment: "Import source: Apple's Journal app. Product name.")
        case .markdown: return String(localized: "Markdown or Text", comment: "Import source: a folder of Markdown or plain-text files")
        case .csv: return String(localized: "CSV", comment: "Import source: a spreadsheet file")
        }
    }

    var subtitle: String {
        switch self {
        case .dayOne: return String(localized: "The ZIP from a JSON export.")
        case .appleJournal: return String(localized: "The exported folder or its ZIP.")
        case .markdown: return String(localized: "A folder or ZIP of .md or .txt files.")
        case .csv: return String(localized: "Needs Date and Text columns.")
        }
    }

    var systemImage: String {
        switch self {
        case .dayOne: return "book.closed"
        case .appleJournal: return "book.pages"
        case .markdown: return "doc.text"
        case .csv: return "tablecells"
        }
    }

    var allowedContentTypes: [UTType] {
        switch self {
        case .dayOne: return [.zip, .json]
        case .appleJournal: return [.folder, .zip, .html]
        case .markdown: return [.folder, .zip, .plainText, UTType(filenameExtension: "md") ?? .plainText]
        case .csv: return [.commaSeparatedText, .tabSeparatedText, .plainText]
        }
    }

    var allowsMultipleSelection: Bool {
        switch self {
        case .appleJournal, .markdown: return true
        case .dayOne, .csv: return false
        }
    }
}

/// One entry read from another app, before it is saved.
struct ImportedEntryDraft: Identifiable, Hashable, Sendable {
    let id = UUID()
    var date: Date
    var text: String
    var mood: Mood?
    var isStarred: Bool = false
    /// Paths of photos inside the import source, in display order.
    var photoPaths: [String] = []
    /// Tags from the source app. Not saved yet (see `JournalImportService.commit`).
    var tags: [String] = []
    /// File name or row the entry came from, for messages.
    var origin: String

    /// A stable identity for dedupe: the minute it was written plus its text, or its photos when it has no text.
    var importKey: UUID {
        JournalImportKey.make(date: date, text: text, photoPaths: photoPaths)
    }
}

struct ImportSkippedItem: Identifiable, Hashable, Sendable {
    enum Reason: String, Sendable {
        case missingDate
        case emptyEntry
        case unreadable
        case photoMissing
    }

    let id = UUID()
    let origin: String
    let reason: Reason

    var reasonText: String {
        switch reason {
        case .missingDate: return String(localized: "No date found", comment: "Why an imported file or row was skipped")
        case .emptyEntry: return String(localized: "No text or photos", comment: "Why an imported file or row was skipped")
        case .unreadable: return String(localized: "Couldn’t be read", comment: "Why an imported file or row was skipped")
        case .photoMissing: return String(localized: "Photo not in the export", comment: "Why an imported photo was skipped")
        }
    }
}

struct JournalImportParseResult: Sendable {
    var drafts: [ImportedEntryDraft] = []
    var skipped: [ImportSkippedItem] = []
}

enum JournalImportError: Error, Equatable {
    /// The files don't match the chosen format.
    case unrecognizedFormat
    /// Nothing could be read from the files.
    case unreadable
    /// CSV without a date or text column.
    case missingColumns

    var message: String {
        switch self {
        case .unrecognizedFormat: return String(localized: "This doesn’t look like that kind of export. Check the format and try again.")
        case .unreadable: return String(localized: "Couldn’t open that file. Try exporting it again.")
        case .missingColumns: return String(localized: "Add Date and Text columns to the CSV and try again.")
        }
    }
}

enum JournalImportKey {
    /// A name-based UUID from SHA-256 of the minute (UTC) and normalized text. Stored on the
    /// block the import creates, so importing the same file twice adds nothing the second time.
    static func make(date: Date, text: String, photoPaths: [String] = []) -> UUID {
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let content = normalizedText.isEmpty
            ? "photos:" + photoPaths.map { ($0 as NSString).lastPathComponent.lowercased() }.sorted().joined(separator: "|")
            : normalizedText
        let material = "offrecord-import|\(minuteFormatter.string(from: date))|\(content)"
        var bytes = Array(SHA256.hash(data: Data(material.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 layout (name-based)
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private static let minuteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter
    }()
}

// MARK: - Sources

/// Files an importer reads: a folder, a ZIP, or a few loose files. Paths are relative and use "/".
protocol JournalImportSource: Sendable {
    var filePaths: [String] { get }
    func data(at path: String) throws -> Data
}

struct DirectoryImportSource: JournalImportSource {
    let root: URL
    let filePaths: [String]

    init(root: URL) {
        // Symlinks resolved on both sides, so /var and /private/var compare equal.
        self.root = root.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = self.root.path.hasSuffix("/") ? self.root.path : self.root.path + "/"
        var paths: [String] = []
        if let enumerator = FileManager.default.enumerator(
            at: self.root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let url as URL in enumerator {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let path = url.resolvingSymlinksInPath().standardizedFileURL.path
                guard path.hasPrefix(rootPath) else { continue }
                paths.append(String(path.dropFirst(rootPath.count)))
            }
        }
        self.filePaths = paths.sorted()
    }

    func data(at path: String) throws -> Data {
        let url = root.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { throw JournalImportError.unreadable }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }
}

struct ZipImportSource: JournalImportSource {
    let archive: ZipArchive
    let filePaths: [String]

    init(archive: ZipArchive) {
        self.archive = archive
        self.filePaths = archive.filePaths
            .filter { !($0 as NSString).lastPathComponent.hasPrefix(".") }
            .sorted()
    }

    func data(at path: String) throws -> Data {
        try archive.contents(at: path)
    }
}

struct InMemoryImportSource: JournalImportSource {
    let files: [String: Data]
    var filePaths: [String] { files.keys.sorted() }

    func data(at path: String) throws -> Data {
        guard let data = files[path] else { throw JournalImportError.unreadable }
        return data
    }
}

/// Several sources read as one, for a multi-file selection.
struct CombinedImportSource: JournalImportSource {
    let sources: [(prefix: String, source: any JournalImportSource)]
    let filePaths: [String]

    init(_ sources: [(prefix: String, source: any JournalImportSource)]) {
        self.sources = sources
        self.filePaths = sources.flatMap { item in item.source.filePaths.map { item.prefix + $0 } }
    }

    func data(at path: String) throws -> Data {
        for item in sources where path.hasPrefix(item.prefix) {
            return try item.source.data(at: String(path.dropFirst(item.prefix.count)))
        }
        throw JournalImportError.unreadable
    }
}

enum JournalImportSources {
    /// Opens a picked URL: a folder, a ZIP (by contents, not name), or a single file.
    static func open(_ url: URL) throws -> any JournalImportSource {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw JournalImportError.unreadable
        }
        if isDirectory.boolValue {
            return DirectoryImportSource(root: url)
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) || data.starts(with: [0x50, 0x4B, 0x05, 0x06]) {
            do {
                return ZipImportSource(archive: try ZipArchive(data: data))
            } catch {
                throw JournalImportError.unreadable
            }
        }
        return InMemoryImportSource(files: [url.lastPathComponent: data])
    }

    /// Opens several picked URLs as one source.
    static func open(_ urls: [URL]) throws -> any JournalImportSource {
        if urls.count == 1, let url = urls.first {
            return try open(url)
        }
        let sources = try urls.enumerated().map { index, url -> (prefix: String, source: any JournalImportSource) in
            let source = try open(url)
            let isSingleFile = source is InMemoryImportSource
            return (prefix: isSingleFile ? "" : "\(index)-\(url.lastPathComponent)/", source: source)
        }
        // Loose files are merged into one in-memory source so their names stay as picked.
        var looseFiles: [String: Data] = [:]
        var nested: [(prefix: String, source: any JournalImportSource)] = []
        for item in sources {
            if let memory = item.source as? InMemoryImportSource {
                looseFiles.merge(memory.files) { first, _ in first }
            } else {
                nested.append(item)
            }
        }
        if !looseFiles.isEmpty {
            nested.append((prefix: "", source: InMemoryImportSource(files: looseFiles)))
        }
        return CombinedImportSource(nested)
    }
}

enum JournalImportPath {
    /// Resolves `relative` (such as "../Resources/IMG.heic") against the folder of `file`.
    static func resolve(_ relative: String, from file: String) -> String {
        var components = file.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if !components.isEmpty { components.removeLast() }
        for part in relative.split(separator: "/", omittingEmptySubsequences: true) {
            switch part {
            case ".": continue
            case "..": if !components.isEmpty { components.removeLast() }
            default: components.append(String(part))
            }
        }
        return components.joined(separator: "/")
    }

    static func folder(of file: String) -> String {
        let parts = file.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: "/") + "/"
    }

    static func fileName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

// MARK: - Shared parsing helpers

enum ImportedMoodMapper {
    private static let synonyms: [String: Mood] = [
        "happy": .happy, "joyful": .happy, "amused": .happy, "good": .happy, "great": .happy,
        "calm": .calm, "peaceful": .calm, "content": .calm, "relieved": .calm, "satisfied": .calm, "relaxed": .calm, "okay": .calm, "ok": .calm,
        "grateful": .grateful, "thankful": .grateful,
        "excited": .excited, "passionate": .excited, "amazed": .excited, "hopeful": .excited, "proud": .excited,
        "tired": .tired, "drained": .tired, "exhausted": .tired, "sleepy": .tired,
        "anxious": .anxious, "worried": .anxious, "stressed": .anxious, "scared": .anxious, "overwhelmed": .anxious, "nervous": .anxious,
        "sad": .sad, "lonely": .sad, "disappointed": .sad, "discouraged": .sad, "hopeless": .sad, "down": .sad, "bad": .sad,
        "angry": .angry, "annoyed": .angry, "frustrated": .angry, "irritated": .angry
    ]

    /// The OffRecord mood for a label like "Calm" or "Sad, Overwhelmed" (the first one that maps wins).
    static func mood(from label: String?) -> Mood? {
        guard let label else { return nil }
        for part in label.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "/" }) {
            let key = part.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let mood = Mood(rawValue: key), mood != .none { return mood }
            if let mood = synonyms[key] { return mood }
        }
        return nil
    }
}

enum ImportedDateParser {
    /// Parses ISO 8601 and common spreadsheet and front-matter dates. Date-only values land at local noon,
    /// so a later time-zone change can't move them to another day.
    static func date(from raw: String, calendar: Calendar = .current) -> Date? {
        let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
        guard !value.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }

        for format in dateTimeFormats {
            if let date = formatter(format, calendar: calendar).date(from: value) { return date }
        }
        for format in dateOnlyFormats {
            if let day = formatter(format, calendar: calendar).date(from: value) {
                return noon(on: day, calendar: calendar)
            }
        }
        return nil
    }

    /// Combines a date-only value with a separate time like "18:30".
    static func date(from rawDate: String, time rawTime: String?, calendar: Calendar = .current) -> Date? {
        let time = rawTime?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !time.isEmpty, let combined = date(from: "\(rawDate.trimmingCharacters(in: .whitespaces)) \(time)", calendar: calendar) {
            return combined
        }
        return date(from: rawDate, calendar: calendar)
    }

    static func noon(on day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .hour, value: 12, to: start) ?? start
    }

    /// Year-month-day with a valid month and day, at local `hour`:`minute`.
    static func date(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0, calendar: Calendar = .current) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day), (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == day,
              calendar.component(.month, from: date) == month else { return nil }
        return date
    }

    private static let dateTimeFormats = [
        "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
        "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm", "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy HH:mm",
        "yyyy-MM-dd h:mm a", "MM/dd/yyyy h:mm a"
    ]
    /// Slash dates are read month first (US), the format most journal apps write.
    private static let dateOnlyFormats = ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd", "MM/dd/yyyy", "M/d/yyyy", "MMMM d, yyyy", "d MMMM yyyy"]

    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.isLenient = false
        formatter.dateFormat = format
        return formatter
    }
}

enum ImportedHTML {
    /// Visible text of an HTML fragment: block ends become line breaks, tags go, entities are decoded.
    static func text(from html: String) -> String {
        var value = html
        value = value.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?i)</(p|div|li|h[1-6]|blockquote|tr)>", with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?i)<li[^>]*>", with: "- ", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        value = decodeEntities(value)
        let lines = value.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [String] = []
        for line in lines {
            if line.isEmpty, result.last?.isEmpty ?? true { continue }
            result.append(line)
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
            "rsquo": "\u{2019}", "lsquo": "\u{2018}", "rdquo": "\u{201D}", "ldquo": "\u{201C}",
            "hellip": "\u{2026}", "mdash": "\u{2014}", "ndash": "\u{2013}"
        ]
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&", let semicolon = text[index...].prefix(12).firstIndex(of: ";") else {
                result.append(character)
                index = text.index(after: index)
                continue
            }
            let name = String(text[text.index(after: index)..<semicolon])
            var replacement: String?
            if name.hasPrefix("#x") || name.hasPrefix("#X") {
                replacement = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else if name.hasPrefix("#") {
                replacement = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
            } else {
                replacement = named[name.lowercased()]
            }
            if let replacement {
                result += replacement
                index = text.index(after: semicolon)
            } else {
                result.append(character)
                index = text.index(after: index)
            }
        }
        return result
    }
}
