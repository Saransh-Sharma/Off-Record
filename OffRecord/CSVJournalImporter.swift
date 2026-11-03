//
//  CSVJournalImporter.swift
//  OffRecord
//
//  Imports a spreadsheet with one entry per row. Headers are matched without
//  regard to case: a date column (Date, Created, Timestamp…), a text column
//  (Text, Entry, Body, Content, Note…), and optionally Time, Mood, and
//  Starred. OffRecord's own CSV export (Date, Time, Mood, Starred, Word
//  Count, Text) imports as is. Commas, semicolons, and tabs are detected
//  from the header row; quoted fields may hold commas, quotes, and line breaks.
//

import Foundation

enum CSVJournalImporter {
    static let dateHeaders: Set<String> = ["date", "created", "created at", "created_at", "creation date", "creationdate", "timestamp", "datetime", "date time", "day", "entry date"]
    static let timeHeaders: Set<String> = ["time", "entry time"]
    static let textHeaders: Set<String> = ["text", "entry", "body", "content", "contents", "note", "notes", "journal", "description"]
    static let moodHeaders: Set<String> = ["mood", "feeling", "emotion"]
    static let starredHeaders: Set<String> = ["starred", "star", "favorite", "favourite", "favorited"]

    static func parse(_ source: any JournalImportSource, calendar: Calendar = .current) throws -> JournalImportParseResult {
        let paths = source.filePaths.filter { ["csv", "tsv", "txt"].contains(($0 as NSString).pathExtension.lowercased()) }
        guard let path = paths.first(where: { $0.lowercased().hasSuffix(".csv") || $0.lowercased().hasSuffix(".tsv") }) ?? paths.first,
              let data = try? source.data(at: path) else {
            throw JournalImportError.unrecognizedFormat
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw JournalImportError.unreadable
        }
        return try parse(text: text, calendar: calendar)
    }

    static func parse(text: String, calendar: Calendar = .current) throws -> JournalImportParseResult {
        var content = text
        if content.hasPrefix("\u{FEFF}") { content.removeFirst() }
        let rows = parseRows(content, delimiter: detectDelimiter(content))
        guard let header = rows.first else { throw JournalImportError.missingColumns }

        let names = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        func column(_ candidates: Set<String>) -> Int? { names.firstIndex(where: candidates.contains) }
        guard let dateColumn = column(dateHeaders), let textColumn = column(textHeaders) else {
            throw JournalImportError.missingColumns
        }
        let timeColumn = column(timeHeaders)
        let moodColumn = column(moodHeaders)
        let starredColumn = column(starredHeaders)

        var result = JournalImportParseResult()
        for (offset, row) in rows.dropFirst().enumerated() {
            let rowNumber = offset + 2
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
            let origin = String(localized: "Row \(rowNumber)", comment: "A row in an imported spreadsheet")
            func value(_ index: Int?) -> String? {
                guard let index, row.indices.contains(index) else { return nil }
                return row[index]
            }

            guard let rawDate = value(dateColumn),
                  let date = ImportedDateParser.date(from: rawDate, time: value(timeColumn), calendar: calendar) else {
                result.skipped.append(ImportSkippedItem(origin: origin, reason: .missingDate))
                continue
            }
            let entryText = (value(textColumn) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entryText.isEmpty else {
                result.skipped.append(ImportSkippedItem(origin: origin, reason: .emptyEntry))
                continue
            }
            let starred = value(starredColumn).map { ["yes", "true", "1", "y", "★", "x"].contains($0.trimmingCharacters(in: .whitespaces).lowercased()) } ?? false
            result.drafts.append(ImportedEntryDraft(
                date: date,
                text: entryText,
                mood: ImportedMoodMapper.mood(from: value(moodColumn)),
                isStarred: starred,
                photoPaths: [],
                tags: [],
                origin: origin
            ))
        }
        return result
    }

    /// The delimiter that appears most in the header row, outside quotes.
    static func detectDelimiter(_ text: String) -> Character {
        var counts: [Character: Int] = [",": 0, ";": 0, "\t": 0]
        var inQuotes = false
        for character in text {
            if character == "\"" { inQuotes.toggle() }
            if character == "\n" || character == "\r\n", !inQuotes { break }
            if !inQuotes, counts[character] != nil { counts[character, default: 0] += 1 }
        }
        return counts.max { $0.value == $1.value ? $0.key != "," : $0.value < $1.value }?.key ?? ","
    }

    /// RFC 4180 rows: quoted fields may contain the delimiter, doubled quotes, and line breaks.
    static func parseRows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character? = iterator.next()

        while let character = pending {
            pending = iterator.next()
            if inQuotes {
                if character == "\"" {
                    if pending == "\"" {
                        field.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
                continue
            }
            switch character {
            case "\"" where field.isEmpty:
                inQuotes = true
            case delimiter:
                row.append(field)
                field = ""
            case "\n", "\r\n", "\r":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            default:
                field.append(character)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
