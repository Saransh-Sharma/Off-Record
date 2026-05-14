import Foundation
import os

enum PerformanceSignposts {
    struct Token {
        #if DEBUG
        let name: StaticString
        let id: OSSignpostID
        #endif
    }

    #if DEBUG
    private static let log = OSLog(subsystem: "com.singularity.offrecord", category: .pointsOfInterest)
    #endif

    static func event(_ name: StaticString) {
        #if DEBUG
        os_signpost(.event, log: log, name: name)
        #endif
    }

    static func begin(_ name: StaticString) -> Token {
        #if DEBUG
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return Token(name: name, id: id)
        #else
        return Token()
        #endif
    }

    static func end(_ token: Token) {
        #if DEBUG
        os_signpost(.end, log: log, name: token.name, signpostID: token.id)
        #endif
    }
}
