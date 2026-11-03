//
//  DayOneImporter.swift
//  OffRecord
//
//  Reads Day One's JSON export: a ZIP with one JSON file per journal (for
//  example Journal.json) whose `entries` array holds `uuid`, `creationDate`
//  (ISO 8601, UTC), Markdown `text`, `starred`, `tags`, and `photos` that
//  point to `photos/<md5>.<type>` next to the JSON. Location and weather are
//  read but not imported. Sources: Day One's "Exporting entries" guide and
//  open-source converters such as danseethaler/dayone-to-md.
//

import Foundation

enum DayOneImporter {
    static func parse(_ source: any JournalImportSource, calendar: Calendar = .current) throws -> JournalImportParseResult {
        let jsonPaths = source.filePaths.filter { $0.lowercased().hasSuffix(".json") }
        guard !jsonPaths.isEmpty else { throw JournalImportError.unrecognizedFormat }

        let filePaths = Set(source.filePaths)
        var result = JournalImportParseResult()
        var foundExport = false

        for jsonPath in jsonPaths {
            guard let data = try? source.data(at: jsonPath) else {
                result.skipped.append(ImportSkippedItem(origin: JournalImportPath.fileName(jsonPath), reason: .unreadable))
                continue
            }
            guard let export = try? JSONDecoder().decode(DayOneExport.self, from: data) else {
                // Other JSON files in the folder aren't journals; only report ones that looked like one.
                if String(decoding: data.prefix(4_096), as: UTF8.self).contains("\"entries\"") {
                    result.skipped.append(ImportSkippedItem(origin: JournalImportPath.fileName(jsonPath), reason: .unreadable))
                }
                continue
            }
            foundExport = true
            let folder = JournalImportPath.folder(of: jsonPath)
            let journalName = (JournalImportPath.fileName(jsonPath) as NSString).deletingPathExtension

            for (index, entry) in export.entries.enumerated() {
                let origin = "\(journalName) #\(index + 1)"
                guard let entry else {
                    result.skipped.append(ImportSkippedItem(origin: origin, reason: .unreadable))
                    continue
                }
                guard let rawDate = entry.creationDate, let date = ImportedDateParser.date(from: rawDate, calendar: calendar) else {
                    result.skipped.append(ImportSkippedItem(origin: origin, reason: .missingDate))
                    continue
                }

                let photos = (entry.photos ?? [])
                    .sorted { ($0.orderInEntry ?? .max) < ($1.orderInEntry ?? .max) }
                var photoPaths: [String] = []
                for photo in photos {
                    guard let md5 = photo.md5, !md5.isEmpty else { continue }
                    let type = (photo.type ?? "jpeg").lowercased()
                    let candidates = [
                        "\(folder)photos/\(md5).\(type)",
                        "\(folder)photos/\(md5).jpg",
                        "\(folder)photos/\(md5).jpeg",
                        "photos/\(md5).\(type)"
                    ]
                    if let path = candidates.first(where: filePaths.contains)
                        ?? filePaths.first(where: { JournalImportPath.fileName($0).hasPrefix(md5 + ".") }) {
                        photoPaths.append(path)
                    } else {
                        result.skipped.append(ImportSkippedItem(origin: "\(origin) · \(md5).\(type)", reason: .photoMissing))
                    }
                }

                let text = cleanedText(entry.text ?? "")
                guard !text.isEmpty || !photoPaths.isEmpty else {
                    result.skipped.append(ImportSkippedItem(origin: origin, reason: .emptyEntry))
                    continue
                }

                result.drafts.append(ImportedEntryDraft(
                    date: date,
                    text: text,
                    mood: nil,
                    isStarred: entry.starred ?? false,
                    photoPaths: photoPaths,
                    tags: entry.tags ?? [],
                    origin: origin
                ))
            }
        }

        guard foundExport else { throw JournalImportError.unrecognizedFormat }
        return result
    }

    /// Day One stores Markdown: inline media as `![](dayone-moment://ID)`, other moments as
    /// `dayone-moment:/…` links, and punctuation escaped with a backslash.
    static func cleanedText(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "\r\n", with: "\n")
        value = value.replacingOccurrences(of: "!\\[[^\\]]*\\]\\(dayone-moment:[^)]*\\)", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\[([^\\]]*)\\]\\(dayone-moment:[^)]*\\)", with: "$1", options: .regularExpression)
        value = value.replacingOccurrences(of: "dayone-moment:/+\\S*", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "(?m)^#{1,6}[ \\t]+", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\\\([\\\\`*_{}\\[\\]()#+\\-.!>~|])", with: "$1", options: .regularExpression)
        let lines = value.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [String] = []
        for line in lines {
            if line.isEmpty, result.last?.isEmpty ?? true { continue }
            result.append(line)
        }
        return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - JSON shape

private struct DayOneExport: Decodable {
    /// Entries that fail to decode become nil so one bad entry doesn't drop the journal.
    let entries: [DayOneEntry?]

    private enum CodingKeys: String, CodingKey { case entries }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var list = try container.nestedUnkeyedContainer(forKey: .entries)
        var entries: [DayOneEntry?] = []
        while !list.isAtEnd {
            let index = list.currentIndex
            if let entry = try? list.decode(DayOneEntry.self) {
                entries.append(entry)
            } else {
                _ = try? list.decode(DayOneSkip.self)
                entries.append(nil)
                if list.currentIndex == index { break }
            }
        }
        self.entries = entries
    }
}

/// Accepts any JSON value, to step past an entry that isn't an object.
private struct DayOneSkip: Decodable {
    init(from decoder: Decoder) throws {}
}

private struct DayOneEntry: Decodable {
    let uuid: String?
    let creationDate: String?
    let text: String?
    let starred: Bool?
    let tags: [String]?
    let photos: [DayOnePhoto]?

    private enum CodingKeys: String, CodingKey { case uuid, creationDate, text, starred, tags, photos }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try? container.decodeIfPresent(String.self, forKey: .uuid)
        creationDate = try? container.decodeIfPresent(String.self, forKey: .creationDate)
        text = try? container.decodeIfPresent(String.self, forKey: .text)
        starred = try? container.decodeIfPresent(Bool.self, forKey: .starred)
        tags = try? container.decodeIfPresent([String].self, forKey: .tags)
        photos = try? container.decodeIfPresent([DayOnePhoto].self, forKey: .photos)
    }
}

private struct DayOnePhoto: Decodable {
    let md5: String?
    let type: String?
    let identifier: String?
    let orderInEntry: Int?

    private enum CodingKeys: String, CodingKey { case md5, type, identifier, orderInEntry }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        md5 = try? container.decodeIfPresent(String.self, forKey: .md5)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        identifier = try? container.decodeIfPresent(String.self, forKey: .identifier)
        orderInEntry = try? container.decodeIfPresent(Int.self, forKey: .orderInEntry)
    }
}
