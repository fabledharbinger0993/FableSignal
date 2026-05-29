import Foundation
import SessionKit

final class SessionStore {
    let sessions: [Session]

    init() {
        let decoder = JSONDecoder()
        sessions = ["relax", "alert", "sleep"].compactMap { name in
            guard
                let url  = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Sessions"),
                let data = try? Data(contentsOf: url),
                let s    = try? decoder.decode(Session.self, from: data)
            else { return nil }
            return s
        }
    }
}
