// JoinLink.swift: the invite link for a join code

import Foundation

/// The web app with the code filled in (web/app.js reads `?join=`). It works
/// from the Camera and for a partner without the iPhone app. The QR code used
/// to hold couplecountdown://join/CODE, which opened nothing: the app
/// registers no such URL scheme.
public enum JoinLink {
    public static let webApp = URL(string: "https://couplecountdown-7715c.web.app/")!

    public static func url(for code: String) -> URL {
        var components = URLComponents(url: webApp, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "join", value: code)]
        return components.url ?? webApp
    }
}
