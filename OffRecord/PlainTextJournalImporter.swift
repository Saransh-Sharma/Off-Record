//
//  PlainTextJournalImporter.swift
//  OffRecord
//
//  Imports a folder (or ZIP) of Markdown and plain-text files, one entry per
//  file, as Obsidian, Bear, iA Writer, and most "export to Markdown" tools
//  write them. The date comes from YAML front matter (`date`, `created`,
//  `created_at`, `creationDate`) or else from the file name
//  ("2024-05-01.md", "2024-05-01 Evening walk.md", "20240501-1830.txt").
//  Files with neither are skipped rather than guessed from file dates.
//

import Foundation

enum PlainTextJournalImporter {
    static let fileExtensions: Set<String> = ["md", "markdown", "txt", "text"]

    static func parse(_ source: any JournalImportSource, calendar: Calendar = .current) throws -> JournalImportParseResult {
        let paths = source.filePaths.filter { fileExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
        guard !paths.isEmpty else { throw JournalImportError.unrecognizedFormat }

        var result = JournalImportParseResult()
        for path in paths {
            let name = JournalImportPath.fileName(path)
            guard let data = try? source.data(at: path),
                  let raw = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                result.skipped.append(ImportSkippedItem(origin: name, reason: .unreadable))
                continue
            }
            let document = parseDocument(raw)
            let date = document.frontMatter.firstValue(for: dateKeys).flatMap { ImportedDateParser.date(from: $0, calendar: calendar) }
                ?? dateFromFileName(name, calendar: calendar)
            guard let date else {
                result.skipped.append(ImportSkippedItem(origin: name, reason: .missingDate))
                continue
            }

            var text = document.body
            if let title = document.frontMatter.firstValue(for: ["title"]), !title.isEmpty,
               !text.lowercased().hasPrefix(title.lowercased()) {
                text = text.isEmpty ? title : title + "\n\n" + text
            }
            guard !text.isEmpty else {
                result.skipped.append(ImportSkippedItem(origin: name, reason: .emptyEntry))
                continue
            }

            let starred = document.frontMatter.firstValue(for: ["starred", "favorite", "favourite", "star"])
                .map { ["true", "yes", "1"].contains($0.lowercased()) } ?? false
            result.drafts.append(ImportedEntryDraft(
                date: date,
                text: text,
                mood: ImportedMoodMapper.mood(from: document.frontMatter.firstValue(for: ["mood", "feeling"])),
                isStarred: starred,
                photoPaths: [],
                tags: document.tags,
                origin: name
            ))
        }
        return result
    }

    static let dateKeys = ["date", "created", "created_at", "createdat", "creationdate", "creation_date", "datetime", "day"]

    struct Document {
        var frontMatter: [String: String]
        var tags: [String]
        var body: String
    }

    /// Splits off YAML front matter (`---` … `---`) and reads simple `key: value` lines and tag lists.
    static func parseDocument(_ raw: String) -> Document {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        var frontMatter: [String: String] = [:]
        var tags: [String] = []

        let lines = text.components(separatedBy: "\n")
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let closing = lines.dropFirst().firstIndex(where: { ["---", "..."].contains($0.trimmingCharacters(in: .whitespaces)) }) {
            var currentListKey: String?
            for line in lines[1..<closing] {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- "), let key = currentListKey {
                    let item = unquoted(String(trimmed.dropFirst(2)))
                    if key == "tags" { tags.append(item) }
                    continue
                }
                guard let colon = trimmed.firstIndex(of: ":") else { continue }
                let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                currentListKey = value.isEmpty ? key : nil
                if key == "tags" || key == "keywords" {
                    let list = value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    tags += list.split(separator: ",").map { unquoted(String($0)) }.filter { !$0.isEmpty }
                } else if !value.isEmpty {
                    frontMatter[key] = unquoted(value)
                }
            }
            text = lines[(closing + 1)...].joined(separator: "\n")
        }
        return Document(frontMatter: frontMatter, tags: tags, body: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A date at the start of a file name, with an optional time: "2024-05-01", "2024_05_01", "20240501",
    /// "2024-05-01 18.30", "2024-05-01T1830".
    static func dateFromFileName(_ name: String, calendar: Calendar = .current) -> Date? {
        let pattern = #/^(\d{4})[-_.]?(\d{2})[-_.]?(\d{2})(?:[ T_-]+(\d{2})[:.\-h]?(\d{2}))?/#
        guard let match = name.firstMatch(of: pattern),
              let year = Int(match.1), let month = Int(match.2), let day = Int(match.3) else { return nil }
        let hour = match.4.flatMap { Int($0) } ?? 12
        let minute = match.5.flatMap { Int($0) } ?? 0
        return ImportedDateParser.date(year: year, month: month, day: day, hour: hour, minute: minute, calendar: calendar)
            ?? ImportedDateParser.date(year: year, month: month, day: day, calendar: calendar)
    }

    private static func unquoted(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
    }
}

private extension Dictionary where Key == String, Value == String {
    func firstValue(for keys: [String]) -> String? {
        for key in keys {
            if let value = self[key], !value.isEmpty { return value }
        }
        return nil
    }
}
