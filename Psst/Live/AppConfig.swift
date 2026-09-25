import Foundation

/// Backend settings from Info.plist, filled from Config/Secrets.xcconfig.
/// Without them the app runs as the labelled local preview.
struct AppConfig {
    let baseURL: URL
    let anonKey: String

    static let live: AppConfig? = {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let host = (info["PSSTSupabaseHost"] as? String)?.trimmingCharacters(in: .whitespaces),
              let key = (info["PSSTSupabaseAnonKey"] as? String)?.trimmingCharacters(in: .whitespaces),
              !host.isEmpty, !key.isEmpty, !host.hasPrefix("$("),
              let url = URL(string: host.contains("://") ? host : "https://\(host)")
        else { return nil }
        return AppConfig(baseURL: url, anonKey: key)
    }()

    /// Public pages (site/, hosted on Vercel).
    static let privacyURL = URL(string: "https://psstapp.fun/privacy")!
    static let termsURL = URL(string: "https://psstapp.fun/terms")!
    static let supportURL = URL(string: "https://psstapp.fun/support")!

    /// APNs environment of this build's device tokens.
    static var pushEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }
}
