import Foundation

enum WatchHomeRoute: String, Hashable {
    case home
    case mood
    case speak
    case record
    case recent

    init?(url: URL) {
        guard url.scheme == "offrecordwatch" else { return nil }
        switch url.host {
        case "home": self = .home
        case "mood": self = .mood
        case "speak": self = .speak
        case "record": self = .record
        case "recent": self = .recent
        default: self = .home
        }
    }

    static func sourceSurface(from url: URL) -> WatchCaptureSourceSurface {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawSource = components.queryItems?.first(where: { $0.name == "source" })?.value,
              let source = WatchCaptureSourceSurface(rawValue: rawSource) else {
            return url.host == "home" ? .complication : .app
        }
        return source
    }
}
