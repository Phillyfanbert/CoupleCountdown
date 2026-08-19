// SharedIdentifiers.swift — placeholder App Group / Keychain identifiers, TBD once the real Xcode project exists (DESIGN.md §5.6)

import Foundation

public enum SharedIdentifiers {
    /// Placeholder — replace with the real App Group identifier once the
    /// Xcode project/entitlements exist (DESIGN.md §5.6).
    public static let appGroup = "group.com.couplecountdown.shared"

    /// Placeholder — real Keychain access groups are prefixed with the
    /// Apple Developer Team ID (e.g. "ABCDE12345.com.couplecountdown.shared"),
    /// which doesn't exist until real code signing does (DESIGN.md §5.6).
    public static let keychainAccessGroup = "group.com.couplecountdown.shared"
}
