import CoreSpotlight
import Foundation
import SwiftUI

enum OffRecordRoute: Equatable {
    case today
    case record
    case timeline(query: String?)
    case entry(UUID)
    case friday(question: String?)
    case weeklyReflectionCurrent
    case weeklyReflection(UUID)
    /// `offrecord://review/month/2026-09`
    case monthInReview(year: Int, month: Int)
    /// `offrecord://review/year/2026`
    case yearInReview(Int)
}

/// A Month in Review or Year in Review to open on Insights.
struct PeriodReviewRoute: Hashable, Identifiable {
    let kind: ReflectionPeriodKind
    let year: Int
    let month: Int?

    var id: String { month.map { "\(year)-\($0)" } ?? "\(year)" }
}

struct TypedNoteRequest: Equatable {
    let id = UUID()
    let promptContext: String?
}

@MainActor
final class OffRecordNavigationRouter: ObservableObject {
    static let shared = OffRecordNavigationRouter()

    nonisolated static let pendingRouteDefaultsKey = "pendingOffRecordRouteURL"

    @Published var selectedTab: OffRecordTab = .today
    @Published var timelineSearchText: String = ""
    @Published var routedEntryID: UUID?
    @Published var fridayQuestion: String?
    @Published var routedWeeklyReflectionID: UUID?
    @Published var shouldOpenCurrentWeeklyReflection = false
    @Published var routedReview: PeriodReviewRoute?
    @Published var shouldStartRecording = false
    /// True while a screen with its own composer (Friday chat) is showing, so the
    /// Record bar doesn't sit on top of it or ride up over it with the keyboard.
    @Published var hidesCaptureAccessory = false
    /// Set when Write is tapped outside Today; Today opens the editor and clears it.
    @Published var pendingTypedNote: TypedNoteRequest?

    private var deferredRoute: OffRecordRoute?

    private init() {}

    func route(_ route: OffRecordRoute, canNavigate: Bool) {
        guard canNavigate else {
            deferredRoute = route
            return
        }
        apply(route)
    }

    func resumeDeferredRouteIfPossible(canNavigate: Bool) {
        guard canNavigate, let route = deferredRoute else { return }
        deferredRoute = nil
        apply(route)
    }

    func consumeStoredRoute(canNavigate: Bool) {
        guard let raw = UserDefaults.standard.string(forKey: Self.pendingRouteDefaultsKey),
              let url = URL(string: raw),
              let route = Self.route(from: url) else {
            return
        }
        if canNavigate {
            self.route(route, canNavigate: true)
            UserDefaults.standard.removeObject(forKey: Self.pendingRouteDefaultsKey)
        } else {
            deferredRoute = route
        }
    }

    func route(userActivity: NSUserActivity, canNavigate: Bool) -> Bool {
        if let rawURL = userActivity.userInfo?["offrecordRouteURL"] as? String,
           let url = URL(string: rawURL),
           let route = Self.route(from: url) {
            self.route(route, canNavigate: canNavigate)
            return true
        }

        if userActivity.activityType == CSSearchableItemActionType,
           let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
           let route = Self.route(fromSpotlightIdentifier: identifier) {
            self.route(route, canNavigate: canNavigate)
            return true
        }

        guard userActivity.activityType == JournalSpotlightIndexer.viewEntryActivityType,
              let identifier = userActivity.persistentIdentifier,
              let route = Self.route(fromSpotlightIdentifier: identifier) else {
            return false
        }

        self.route(route, canNavigate: canNavigate)
        return true
    }

    func clearEntryRouteIfNeeded(_ id: UUID?) {
        guard routedEntryID == id else { return }
        routedEntryID = nil
    }

    func clearFridayQuestion(_ question: String?) {
        guard fridayQuestion == question else { return }
        fridayQuestion = nil
    }

    private func apply(_ route: OffRecordRoute) {
        switch route {
        case .today:
            selectedTab = .today
        case .record:
            // Capture is available from every tab; stay where the person is.
            shouldStartRecording = true
        case .timeline(let query):
            selectedTab = .timeline
            timelineSearchText = query ?? ""
        case .entry(let id):
            selectedTab = .timeline
            routedEntryID = id
        case .friday(let question):
            selectedTab = .friday
            // With Friday off the tab shows her off state, and the question is dropped.
            fridayQuestion = FridayAvailability.isEnabled ? question : nil
        case .weeklyReflectionCurrent:
            selectedTab = .insights
            routedWeeklyReflectionID = nil
            shouldOpenCurrentWeeklyReflection = true
        case .weeklyReflection(let id):
            selectedTab = .insights
            shouldOpenCurrentWeeklyReflection = false
            routedWeeklyReflectionID = id
        case .monthInReview(let year, let month):
            selectedTab = .insights
            routedReview = PeriodReviewRoute(kind: .month, year: year, month: month)
        case .yearInReview(let year):
            selectedTab = .insights
            routedReview = PeriodReviewRoute(kind: .year, year: year, month: nil)
        }
    }

    func requestTypedNote(promptContext: String? = nil) {
        selectedTab = .today
        pendingTypedNote = TypedNoteRequest(promptContext: promptContext)
    }

    nonisolated static func storePendingRoute(_ route: OffRecordRoute) {
        guard let url = url(for: route) else { return }
        UserDefaults.standard.set(url.absoluteString, forKey: pendingRouteDefaultsKey)
    }

    nonisolated static func route(from url: URL) -> OffRecordRoute? {
        guard url.scheme == "offrecord" else { return nil }

        let host = url.host?.lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = queryItems.first(where: { $0.name == "query" })?.value
        let question = queryItems.first(where: { $0.name == "question" })?.value

        switch host {
        case "today":
            return .today
        case "record":
            return .record
        case "timeline":
            return .timeline(query: query)
        case "entry":
            guard let rawID = pathComponents.first, let id = UUID(uuidString: rawID) else { return nil }
            return .entry(id)
        case "friday":
            return .friday(question: question)
        case "weekly-reflection":
            if pathComponents.first?.lowercased() == "current" {
                return .weeklyReflectionCurrent
            }
            guard let rawID = pathComponents.first, let id = UUID(uuidString: rawID) else {
                return nil
            }
            return .weeklyReflection(id)
        case "review":
            return reviewRoute(pathComponents)
        default:
            return nil
        }
    }

    /// `year/2026` or `month/2026-09`. Years run 1–9999 and months 1–12.
    nonisolated private static func reviewRoute(_ components: [String]) -> OffRecordRoute? {
        guard components.count == 2 else { return nil }
        let value = components[1]
        let isDigit: (Character) -> Bool = { $0.isASCII && $0.isNumber }
        switch components[0].lowercased() {
        case "year":
            guard value.count == 4, value.allSatisfy(isDigit), let year = Int(value), year >= 1 else { return nil }
            return .yearInReview(year)
        case "month":
            let parts = value.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0].count == 4, (1...2).contains(parts[1].count),
                  parts.allSatisfy({ $0.allSatisfy(isDigit) }),
                  let year = Int(parts[0]), let month = Int(parts[1]),
                  year >= 1, (1...12).contains(month) else { return nil }
            return .monthInReview(year: year, month: month)
        default:
            return nil
        }
    }

    nonisolated static func url(for route: OffRecordRoute) -> URL? {
        var components = URLComponents()
        components.scheme = "offrecord"

        switch route {
        case .today:
            components.host = "today"
        case .record:
            components.host = "record"
        case .timeline(let query):
            components.host = "timeline"
            if let query, !query.isEmpty {
                components.queryItems = [URLQueryItem(name: "query", value: query)]
            }
        case .entry(let id):
            components.host = "entry"
            components.path = "/\(id.uuidString)"
        case .friday(let question):
            components.host = "friday"
            if let question, !question.isEmpty {
                components.queryItems = [URLQueryItem(name: "question", value: question)]
            }
        case .weeklyReflectionCurrent:
            components.host = "weekly-reflection"
            components.path = "/current"
        case .weeklyReflection(let id):
            components.host = "weekly-reflection"
            components.path = "/\(id.uuidString)"
        case .monthInReview(let year, let month):
            components.host = "review"
            components.path = String(format: "/month/%04d-%02d", year, month)
        case .yearInReview(let year):
            components.host = "review"
            components.path = String(format: "/year/%04d", year)
        }

        return components.url
    }

    nonisolated static func route(fromSpotlightIdentifier identifier: String) -> OffRecordRoute? {
        let rawID = identifier.hasPrefix(JournalSpotlightIndexer.entryIdentifierPrefix)
            ? String(identifier.dropFirst(JournalSpotlightIndexer.entryIdentifierPrefix.count))
            : identifier
        guard let id = UUID(uuidString: rawID) else { return nil }
        return .entry(id)
    }
}
