//
//  AppleJournalImporter.swift
//  OffRecord
//
//  Reads the export from Apple's Journal app (Settings → Apps → Journal →
//  Export, or the app's own Export). The export is a folder, often zipped,
//  named AppleJournalEntries with:
//
//    Entries/2024-08-28_Evening_walk.html   one HTML file per entry
//    Entries/2024-08-30_(1).html            a second entry on the same day
//    Resources/<asset-id>.heic              photos, videos, audio, maps
//    index.html                             a list of entries (skipped)
//
//  In each entry, `.pageHeader` holds the long date, `.assetGrid` holds
//  `.gridItem assetType_photo` items with `<img class="asset_image"
//  src="../Resources/…">`, `.title` the title, `.reflectionPrompt` the
//  prompt, and `.bodyText` the paragraphs. `assetType_stateOfMind` items
//  carry State of Mind labels such as "Calm". The file name's date is used
//  first; `.pageHeader` is a fallback. There's no time of day, so entries
//  land at noon. Sources: obsidian-importer's Apple Journal format and test
//  fixtures, and tarikbc/apple-journal-importer.
//

import Foundation

enum AppleJournalImporter {
    static func parse(_ source: any JournalImportSource, calendar: Calendar = .current) throws -> JournalImportParseResult {
        let htmlPaths = source.filePaths.filter { path in
            let lower = path.lowercased()
            return (lower.hasSuffix(".html") || lower.hasSuffix(".htm"))
                && JournalImportPath.fileName(lower) != "index.html"
        }
        // Prefer files under an Entries folder when there is one.
        let entryPaths = htmlPaths.contains(where: isInEntriesFolder) ? htmlPaths.filter(isInEntriesFolder) : htmlPaths
        guard !entryPaths.isEmpty else { throw JournalImportError.unrecognizedFormat }

        let filePaths = Set(source.filePaths)
        var result = JournalImportParseResult()
        var sawJournalMarkup = false

        for path in entryPaths {
            let name = JournalImportPath.fileName(path)
            guard let data = try? source.data(at: path) else {
                result.skipped.append(ImportSkippedItem(origin: name, reason: .unreadable))
                continue
            }
            let html = String(decoding: data, as: UTF8.self)
            let entry = parseEntry(html: html, path: path, calendar: calendar)
            sawJournalMarkup = sawJournalMarkup || entry.hasJournalMarkup

            guard let date = entry.date else {
                result.skipped.append(ImportSkippedItem(origin: name, reason: .missingDate))
                continue
            }

            var photoPaths: [String] = []
            for reference in entry.photoReferences {
                let resolved = JournalImportPath.resolve(reference, from: path)
                if filePaths.contains(resolved) {
                    photoPaths.append(resolved)
                } else if let match = source.filePaths.first(where: { JournalImportPath.fileName($0) == JournalImportPath.fileName(resolved) }) {
                    photoPaths.append(match)
                } else {
                    result.skipped.append(ImportSkippedItem(origin: "\(name) · \(JournalImportPath.fileName(resolved))", reason: .photoMissing))
                }
            }

            guard !entry.text.isEmpty || !photoPaths.isEmpty else {
                result.skipped.append(ImportSkippedItem(origin: name, reason: .emptyEntry))
                continue
            }

            result.drafts.append(ImportedEntryDraft(
                date: date,
                text: entry.text,
                mood: entry.mood,
                isStarred: false,
                photoPaths: photoPaths,
                tags: [],
                origin: name
            ))
        }

        // Plain HTML files that aren't Journal pages and have no dated names aren't this format.
        if !sawJournalMarkup, result.drafts.isEmpty {
            throw JournalImportError.unrecognizedFormat
        }
        return result
    }

    struct ParsedEntry {
        var date: Date?
        var text: String
        var mood: Mood?
        var photoReferences: [String]
        var hasJournalMarkup: Bool
    }

    static func parseEntry(html: String, path: String, calendar: Calendar = .current) -> ParsedEntry {
        let fileName = JournalImportPath.fileName(path)
        let hasMarkup = html.contains("pageHeader") || html.contains("bodyText") || html.contains("assetGrid")
        let date = dateFromFileName(fileName, calendar: calendar)
            ?? firstMatch(#"class=["']pageHeader["'][^>]*>(.*?)</div>"#, in: html).flatMap { dateFromHeader(ImportedHTML.text(from: $0), calendar: calendar) }

        let prompt = firstMatch(#"class=["']reflectionPrompt["'][^>]*>(.*?)</div>"#, in: html).map(ImportedHTML.text(from:)) ?? ""
        let title = firstMatch(#"class=["']title["'][^>]*>(.*?)</div>"#, in: html).map(ImportedHTML.text(from:)) ?? ""
        let body = bodyText(in: html)
        let text = [prompt, title, body].filter { !$0.isEmpty }.joined(separator: "\n\n")

        return ParsedEntry(
            date: date,
            text: text,
            mood: stateOfMindMood(in: html),
            photoReferences: photoReferences(in: html),
            hasJournalMarkup: hasMarkup
        )
    }

    // MARK: - Dates

    /// "2024-08-28.html", "2024-08-28_Evening_walk.html", or "2024-08-30_(1).html" (a second entry that day).
    static func dateFromFileName(_ name: String, calendar: Calendar = .current) -> Date? {
        guard let match = name.firstMatch(of: #/^(\d{4})-(\d{2})-(\d{2})(?:_(.*))?\.html?$/#.ignoresCase()),
              let year = Int(match.1), let month = Int(match.2), let day = Int(match.3) else { return nil }
        var order = 0
        if let rest = match.4.map(String.init), let duplicate = rest.firstMatch(of: #/^\((\d+)\)$/#), let number = Int(duplicate.1) {
            order = min(number, 59)
        }
        // Noon, with later same-day entries a minute apart so they keep their order.
        return ImportedDateParser.date(year: year, month: month, day: day, hour: 12, minute: order, calendar: calendar)
    }

    /// The header's long date, such as "Sunday, 3 November 2024" or "Sunday, November 3, 2024".
    static func dateFromHeader(_ header: String, calendar: Calendar = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        for format in ["EEEE, d MMMM yyyy", "EEEE, MMMM d, yyyy", "EEEE d MMMM yyyy", "d MMMM yyyy", "MMMM d, yyyy"] {
            formatter.dateFormat = format
            if let day = formatter.date(from: header.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return ImportedDateParser.noon(on: day, calendar: calendar)
            }
        }
        return nil
    }

    // MARK: - Content

    /// Paragraphs after the `bodyText` marker. The export nests its divs inside `<p><span>`,
    /// so the body is read from the marker to the end of the page.
    static func bodyText(in html: String) -> String {
        guard let marker = html.range(of: #"class=["']bodyText["'][^>]*>"#, options: .regularExpression) else { return "" }
        var tail = String(html[marker.upperBound...])
        if let end = tail.range(of: "</body>", options: .caseInsensitive) {
            tail = String(tail[..<end.lowerBound])
        }
        return ImportedHTML.text(from: tail)
    }

    /// `src` of each photo item's image, in page order. Videos, audio, maps, and other cards are left out.
    static func photoReferences(in html: String) -> [String] {
        let itemPattern = #"<div[^>]*class=["'][^"']*assetType_(\w+)[^"']*["'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: itemPattern) else { return [] }
        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        var references: [String] = []
        for (index, match) in matches.enumerated() {
            let type = nsHTML.substring(with: match.range(at: 1))
            guard type == "photo" || type == "livePhoto" else { continue }
            let segmentStart = match.range.location + match.range.length
            let segmentEnd = index + 1 < matches.count ? matches[index + 1].range.location : nsHTML.length
            let segment = nsHTML.substring(with: NSRange(location: segmentStart, length: max(0, segmentEnd - segmentStart)))
            let source = firstMatch(#"<img[^>]*class=["'][^"']*asset_image[^"']*["'][^>]*src=["']([^"']+)["']"#, in: segment)
                ?? firstMatch(#"<img[^>]*src=["']([^"']+)["'][^>]*class=["'][^"']*asset_image"#, in: segment)
                ?? firstMatch(#"<img[^>]*src=["']([^"']+)["']"#, in: segment)
            guard let source else { continue }
            let decoded = ImportedHTML.decodeEntities(source).removingPercentEncoding ?? source
            references.append(decoded)
        }
        return references
    }

    /// The first State of Mind label that maps to an OffRecord mood.
    static func stateOfMindMood(in html: String) -> Mood? {
        let pattern = #"assetType_stateOfMind[^>]*>\s*<div[^>]*gridItemOverlayHeader[^>]*>(.*?)</div>"#
        return firstMatch(pattern, in: html).flatMap { ImportedMoodMapper.mood(from: ImportedHTML.text(from: $0)) }
    }

    private static func isInEntriesFolder(_ path: String) -> Bool {
        path.split(separator: "/").dropLast().contains { $0.caseInsensitiveCompare("Entries") == .orderedSame }
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}
