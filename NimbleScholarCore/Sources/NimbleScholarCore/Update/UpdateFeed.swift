import Foundation

/// Builds the GitHub Releases URLs Sparkle uses to find and download updates.
///
/// Every release is published as an asset on a single rolling GitHub Release under
/// the fixed tag `channelTag`, so these URLs stay stable across versions. The
/// Info.plist `SUFeedURL` must equal `UpdateFeed.appcastURLString`.
public enum UpdateFeed {
    public static let owner = "yijie21"
    public static let repo = "NimbleScholar"
    public static let channelTag = "updates"

    /// Base URL for downloadable assets on the rolling release.
    public static var downloadPrefix: String {
        "https://github.com/\(owner)/\(repo)/releases/download/\(channelTag)/"
    }

    /// The appcast feed URL (matches Info.plist `SUFeedURL`).
    public static var appcastURLString: String {
        downloadPrefix + "appcast.xml"
    }

    public static var appcastURL: URL {
        URL(string: appcastURLString)!
    }
}
