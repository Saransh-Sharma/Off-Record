import Foundation
import Testing
@testable import OffRecord

/// Parsing for each import format, from fixtures built here (folders and ZIPs), including malformed input.
struct JournalImporterTests {

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private func components(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    // MARK: - Day One

    private let dayOneJournal = """
    {"metadata":{"version":"1.0"},"entries":[
      {"uuid":"A1","creationDate":"2025-03-04T16:15:00Z","modifiedDate":"2025-03-04T16:20:00Z","timeZone":"America/Los_Angeles",
       "text":"# Morning\\n\\nWalked to the lake\\\\. It was cold\\\\!\\n\\n![](dayone-moment://P1)",
       "starred":true,"tags":["walks","outside"],
       "photos":[{"identifier":"P1","md5":"abc123","type":"png","orderInEntry":0},{"identifier":"P2","md5":"missing","type":"jpeg","orderInEntry":1}],
       "location":{"placeName":"Lake Merritt","latitude":37.8},"weather":{"temperatureCelsius":4}},
      {"uuid":"A2","creationDate":"2025-03-05T03:40:12.500Z","text":"Dinner with Sam."},
      {"uuid":"A3","text":"This one has no date."},
      {"uuid":"A4","creationDate":"2025-03-06T10:00:00Z","text":"   "},
      "not an entry"
    ]}
    """

    private let travelJournal = """
    {"entries":[{"uuid":"T1","creationDate":"2025-04-10T20:00:00Z","text":"Landed in Lisbon.","starred":false}]}
    """

    @Test func dayOneZipWithTwoJournalsImportsEveryDatedEntry() throws {
        let zip = ImportTestFixtures.zip([
            .init(path: "Journal.json", data: Data(dayOneJournal.utf8)),
            .init(path: "Travel.json", data: Data(travelJournal.utf8)),
            .init(path: "photos/abc123.png", data: ImportTestFixtures.pngData, deflate: false)
        ])
        let source = ZipImportSource(archive: try ZipArchive(data: zip))

        let result = try DayOneImporter.parse(source, calendar: calendar)

        #expect(result.drafts.count == 3)
        let morning = try #require(result.drafts.first { $0.origin == "Journal #1" })
        #expect(morning.text == "Morning\n\nWalked to the lake. It was cold!")
        #expect(morning.isStarred)
        #expect(morning.tags == ["walks", "outside"])
        #expect(morning.photoPaths == ["photos/abc123.png"])
        #expect(components(morning.date).hour == 8 && components(morning.date).minute == 15)

        let dinner = try #require(result.drafts.first { $0.text == "Dinner with Sam." })
        #expect(components(dinner.date).day == 4) // 03:40 UTC on the 5th is the evening of the 4th in Los Angeles
        #expect(result.drafts.contains { $0.text == "Landed in Lisbon." })

        let reasons = result.skipped.map(\.reason)
        #expect(reasons.filter { $0 == .missingDate }.count == 1)
        #expect(reasons.filter { $0 == .emptyEntry }.count == 1)
        #expect(reasons.filter { $0 == .unreadable }.count == 1)
        #expect(reasons.filter { $0 == .photoMissing }.count == 1)
    }

    @Test func dayOneMarkdownIsCleanedUp() {
        let text = "## Title\n\nA list\\:\n\\- one\n[Workout](dayone-moment:/workout/123)\ndayone-moment:/location/9\n\n\n\nEnd\\."
        #expect(DayOneImporter.cleanedText(text) == "Title\n\nA list\\:\n- one\nWorkout\n\nEnd.")
    }

    @Test func dayOneRejectsOtherFiles() throws {
        let notDayOne = InMemoryImportSource(files: ["settings.json": Data(#"{"theme":"dark"}"#.utf8)])
        #expect(throws: JournalImportError.unrecognizedFormat) { try DayOneImporter.parse(notDayOne) }

        let noJSON = InMemoryImportSource(files: ["notes.txt": Data("hello there".utf8)])
        #expect(throws: JournalImportError.unrecognizedFormat) { try DayOneImporter.parse(noJSON) }

        let truncated = InMemoryImportSource(files: ["Journal.json": Data(dayOneJournal.prefix(120).utf8)])
        #expect(throws: JournalImportError.unrecognizedFormat) { try DayOneImporter.parse(truncated) }
    }

    @Test func dayOneJSONCanBePickedWithoutAZip() throws {
        let source = InMemoryImportSource(files: ["Travel.json": Data(travelJournal.utf8)])
        let result = try DayOneImporter.parse(source, calendar: calendar)
        #expect(result.drafts.map(\.text) == ["Landed in Lisbon."])
    }

    // MARK: - Apple Journal

    private func appleJournalPage(header: String, title: String = "", body: [String], assets: String = "", prompt: String = "") -> String {
        let paragraphs = body.map { "<p class=\"p2\"><span class=\"s2\">\($0)</span></p>" }.joined(separator: "\n")
        let promptDiv = prompt.isEmpty ? "" : "<div class='reflectionPrompt'>\(prompt)</div>"
        return """
        <!DOCTYPE html>
        <html dir="auto">
        <head><meta http-equiv="Content-Type" content="text/html; charset=UTF-8"><title></title></head>
        <body>
        <p class="p1"><span class="s1"><div class='pageContainer'>    <div class="pageHeader">\(header)</div>    <div class="assetGrid">\(assets)</div>\(promptDiv)<div class='title'>\(title)</div><div class='bodyText'></span></p>
        \(paragraphs)
        <p class="p1"><span class="s1"></div></div></span></p>
        </body>
        </html>
        """
    }

    private var appleJournalFiles: [String: Data] {
        let assets = """
        <div id="MOOD1" class="gridItem assetType_stateOfMind">
            <div class="gridItemOverlayText gridItemOverlayHeader">Sad, Overwhelmed</div>
            <img src="../Resources/MOOD1.heic" class="asset_image"/>
            <div class="gridItemOverlayText gridItemOverlayFooter">Health</div>
        </div>    <div id="IMG%202" class="gridItem assetType_photo">
            <img src="../Resources/IMG%202.png" class="asset_image"/>
        </div>    <div id="VID1" class="gridItem assetType_video">
            <video src="../Resources/VID1.mov"></video>
        </div>
        """
        return [
            "AppleJournalEntries/index.html": Data("<html><body>Index</body></html>".utf8),
            "AppleJournalEntries/Entries/2024-11-03.html": Data(appleJournalPage(
                header: "Sunday, 3 November 2024",
                title: "Rough Day",
                body: ["Work ran late &amp; I skipped lunch.", "Called Mom on the way home. It&#8217;s fine."],
                assets: assets,
                prompt: "What made today hard?"
            ).utf8),
            "AppleJournalEntries/Entries/2024-11-03_(1).html": Data(appleJournalPage(header: "Sunday, 3 November 2024", body: ["A second note that night."]).utf8),
            "AppleJournalEntries/Entries/2024-08-28_Evening_walk.html": Data(appleJournalPage(header: "Wednesday, 28 August 2024", title: "Evening walk", body: ["Sunset by the water."]).utf8),
            "AppleJournalEntries/Entries/Untitled.html": Data(appleJournalPage(header: "Tuesday, 5 March 2024", body: ["Named without a date."]).utf8),
            "AppleJournalEntries/Entries/Undated.html": Data(appleJournalPage(header: "", body: ["No date anywhere."]).utf8),
            "AppleJournalEntries/Resources/IMG 2.png": ImportTestFixtures.pngData,
            "AppleJournalEntries/Resources/VID1.mov": Data([0, 1, 2])
        ]
    }

    @Test func appleJournalFolderImportsEntriesPhotosAndMood() throws {
        let root = try ImportTestFixtures.temporaryDirectory()
        try ImportTestFixtures.write(appleJournalFiles, under: root)

        let result = try AppleJournalImporter.parse(DirectoryImportSource(root: root), calendar: calendar)

        #expect(result.drafts.count == 4)
        let rough = try #require(result.drafts.first { $0.origin == "2024-11-03.html" })
        #expect(rough.text == "What made today hard?\n\nRough Day\n\nWork ran late & I skipped lunch.\n\nCalled Mom on the way home. It\u{2019}s fine.")
        #expect(rough.mood == .sad)
        #expect(rough.photoPaths == ["AppleJournalEntries/Resources/IMG 2.png"])
        #expect(components(rough.date).hour == 12 && components(rough.date).minute == 0)

        let second = try #require(result.drafts.first { $0.origin == "2024-11-03_(1).html" })
        #expect(second.date > rough.date)
        #expect(components(second.date).day == 3)

        let walk = try #require(result.drafts.first { $0.origin == "2024-08-28_Evening_walk.html" })
        #expect(walk.text == "Evening walk\n\nSunset by the water.")

        // Without a dated file name, the page header gives the date.
        let untitled = try #require(result.drafts.first { $0.origin == "Untitled.html" })
        #expect(components(untitled.date).month == 3 && components(untitled.date).day == 5)

        #expect(result.skipped.map(\.reason) == [.missingDate])
        #expect(!result.drafts.contains { $0.origin == "index.html" })
    }

    @Test func appleJournalZipMatchesTheFolder() throws {
        let zip = ImportTestFixtures.zip(appleJournalFiles.map { ImportTestFixtures.ZipFile(path: $0.key, data: $0.value) })
        let result = try AppleJournalImporter.parse(ZipImportSource(archive: try ZipArchive(data: zip)), calendar: calendar)
        #expect(result.drafts.count == 4)
        #expect(result.drafts.first { $0.origin == "2024-11-03.html" }?.photoPaths == ["AppleJournalEntries/Resources/IMG 2.png"])
    }

    @Test func appleJournalRejectsUnrelatedHTML() {
        let source = InMemoryImportSource(files: ["page.html": Data("<html><body><p>Hello</p></body></html>".utf8)])
        #expect(throws: JournalImportError.unrecognizedFormat) { try AppleJournalImporter.parse(source) }
        #expect(throws: JournalImportError.unrecognizedFormat) {
            try AppleJournalImporter.parse(InMemoryImportSource(files: ["a.txt": Data("x".utf8)]))
        }
    }

    @Test func appleJournalFileNamesGiveDateAndOrder() {
        let first = AppleJournalImporter.dateFromFileName("2024-08-30.html", calendar: calendar)
        let second = AppleJournalImporter.dateFromFileName("2024-08-30_(1).html", calendar: calendar)
        #expect(first != nil && second != nil)
        #expect(first! < second!)
        #expect(AppleJournalImporter.dateFromFileName("2024-02-30.html", calendar: calendar) == nil)
        #expect(AppleJournalImporter.dateFromFileName("notes.html", calendar: calendar) == nil)
    }

    // MARK: - Markdown and text

    @Test func markdownFolderReadsFrontMatterAndFileNames() throws {
        let root = try ImportTestFixtures.temporaryDirectory()
        try ImportTestFixtures.write([
            "2024-05-01.md": Data("Morning pages.\n\nSecond paragraph.".utf8),
            "notes/evening.md": Data("""
            ---
            title: "Evening"
            date: 2024-05-02 21:15
            mood: Calm
            starred: yes
            tags: [garden, family]
            ---
            Watered the tomatoes.
            """.utf8),
            "notes/list.markdown": Data("""
            ---
            created: 2024-05-04T07:30:00Z
            tags:
              - run
            ---
            Ran 5k.
            """.utf8),
            "20240503-0730 Run.txt": Data("Early run.".utf8),
            "random.txt": Data("No date here.".utf8),
            "empty 2024-06-01.md": Data("".utf8),
            "2024-06-02.md": Data("   \n".utf8),
            "photo.png": ImportTestFixtures.pngData
        ], under: root)

        let result = try PlainTextJournalImporter.parse(DirectoryImportSource(root: root), calendar: calendar)
        let byOrigin = Dictionary(uniqueKeysWithValues: result.drafts.map { ($0.origin, $0) })

        #expect(result.drafts.count == 4)
        #expect(byOrigin["2024-05-01.md"]?.text == "Morning pages.\n\nSecond paragraph.")
        #expect(components(byOrigin["2024-05-01.md"]!.date).hour == 12)

        let evening = try #require(byOrigin["evening.md"])
        #expect(evening.text == "Evening\n\nWatered the tomatoes.")
        #expect(evening.mood == .calm)
        #expect(evening.isStarred)
        #expect(evening.tags == ["garden", "family"])
        #expect(components(evening.date).hour == 21 && components(evening.date).minute == 15)

        #expect(byOrigin["list.markdown"]?.tags == ["run"])
        #expect(components(byOrigin["20240503-0730 Run.txt"]!.date).hour == 7)

        #expect(result.skipped.filter { $0.reason == .missingDate }.map(\.origin).sorted() == ["empty 2024-06-01.md", "random.txt"])
        #expect(result.skipped.filter { $0.reason == .emptyEntry }.map(\.origin) == ["2024-06-02.md"])
    }

    @Test func markdownNeedsTextFiles() {
        #expect(throws: JournalImportError.unrecognizedFormat) {
            try PlainTextJournalImporter.parse(InMemoryImportSource(files: ["a.png": ImportTestFixtures.pngData]))
        }
    }

    // MARK: - CSV

    @Test func csvReadsOffRecordsOwnExport() throws {
        let csv = """
        Date,Time,Mood,Starred,Word Count,Text
        2024-07-01,18:30,happy,Yes,4,"Picnic, then a nap."
        2024-07-02,07:05,,No,3,"She said ""hi"" back."
        """
        let result = try CSVJournalImporter.parse(text: csv, calendar: calendar)

        #expect(result.drafts.count == 2)
        #expect(result.drafts[0].text == "Picnic, then a nap.")
        #expect(result.drafts[0].mood == .happy)
        #expect(result.drafts[0].isStarred)
        #expect(components(result.drafts[0].date).hour == 18 && components(result.drafts[0].date).minute == 30)
        #expect(result.drafts[1].text == "She said \"hi\" back.")
        #expect(!result.drafts[1].isStarred)
    }

    @Test func csvHandlesOtherHeadersDelimitersAndLineBreaks() throws {
        let csv = "\u{FEFF}ENTRY DATE;Entry;Feeling\r\n2024-07-03;\"Two lines;\r\nin one cell\";Anxious\r\nnot a date;Skipped row;\r\n2024-07-05;;Calm\r\n\r\n07/06/2024;US date;tired\r\n"
        let result = try CSVJournalImporter.parse(text: csv, calendar: calendar)

        #expect(result.drafts.count == 2)
        #expect(result.drafts[0].text == "Two lines;\r\nin one cell" || result.drafts[0].text == "Two lines;\nin one cell")
        #expect(result.drafts[0].mood == .anxious)
        #expect(components(result.drafts[1].date).month == 7 && components(result.drafts[1].date).day == 6)
        #expect(result.drafts[1].mood == .tired)
        #expect(result.skipped.map(\.reason) == [.missingDate, .emptyEntry])
    }

    @Test func csvWithoutDateOrTextColumnsIsRejected() {
        #expect(throws: JournalImportError.missingColumns) {
            try CSVJournalImporter.parse(text: "Title,Body\nA,B\n")
        }
        #expect(throws: JournalImportError.missingColumns) {
            try CSVJournalImporter.parse(text: "")
        }
    }

    // MARK: - Shared helpers

    @Test func importKeysAreStableAndIgnoreSpacing() {
        let date = Date(timeIntervalSince1970: 1_720_000_000)
        let key = JournalImportKey.make(date: date, text: "Walked to the lake.")
        #expect(key == JournalImportKey.make(date: date.addingTimeInterval(10), text: "  Walked  to the\nlake. "))
        #expect(key != JournalImportKey.make(date: date.addingTimeInterval(120), text: "Walked to the lake."))
        #expect(key != JournalImportKey.make(date: date, text: "Walked to the river."))
        #expect(JournalImportKey.make(date: date, text: "", photoPaths: ["a/IMG1.png"]) == JournalImportKey.make(date: date, text: "", photoPaths: ["b/img1.png"]))
    }

    @Test func pathsResolveRelativeToTheEntry() {
        #expect(JournalImportPath.resolve("../Resources/IMG.heic", from: "Export/Entries/2024-01-01.html") == "Export/Resources/IMG.heic")
        #expect(JournalImportPath.resolve("./a.png", from: "x.html") == "a.png")
        #expect(JournalImportPath.resolve("../../../../etc/passwd", from: "a/b.html") == "etc/passwd")
    }

    @Test func moodLabelsMapConservatively() {
        #expect(ImportedMoodMapper.mood(from: "Calm") == .calm)
        #expect(ImportedMoodMapper.mood(from: "Indifferent, Stressed") == .anxious)
        #expect(ImportedMoodMapper.mood(from: "GRATEFUL") == .grateful)
        #expect(ImportedMoodMapper.mood(from: "Indifferent") == nil)
        #expect(ImportedMoodMapper.mood(from: nil) == nil)
    }

    @Test func htmlEntitiesDecode() {
        #expect(ImportedHTML.decodeEntities("A &amp; B &lt;3 &#8217; &#x2019; &nbsp;&unknown;") == "A & B <3 \u{2019} \u{2019}  &unknown;")
    }
}
