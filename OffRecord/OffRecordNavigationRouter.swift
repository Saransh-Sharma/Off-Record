import CoreSpotlight
import Foundation
import SwiftUI

enum OffRecordRoute: Equatable {
    case today
    case record
    case timeline(query: String?)
    case entry(UUID)
    case friday(question: String?)
}

@MainActor
final class OffRecordNavigationRouter: ObservableObject {
    static let shared = OffRecordNavigationRouter()

    nonisolated static let pendingRouteDefaultsKey = "pendingOffRecordRouteURL"

    @Published var selectedTab: OffRecordTab = .today
    @Published var timelineSearchText: String = ""
    @Published var routedEntryID: UUID?
    @Published var fridayQuestion: String?
    @Published var shouldStartRecording = false

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
        UserDefaults.standard.removeObject(forKey: Self.pendingRouteDefaultsKey)
        self.route(route, canNavigate: canNavigate)
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
            selectedTab = .today
            shouldStartRecording = true
        case .timeline(let query):
            selectedTab = .timeline
            timelineSearchText = query ?? ""
        case .entry(let id):
            selectedTab = .timeline
            routedEntryID = id
        case .friday(let question):
            selectedTab = .friday
            fridayQuestion = question
        }
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
