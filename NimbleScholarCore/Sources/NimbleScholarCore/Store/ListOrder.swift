import Foundation

/// Keeps a list's on-screen order stable across background refreshes: background
/// enrichment writes (figures, PDFs, links) must not reshuffle the library under
/// the user's cursor.
public enum ListOrder {
    /// `fresh` rearranged into `current`'s order, when both hold exactly the same
    /// ids (each exactly once). Returns nil when the id sets differ, ids repeat,
    /// or any row lacks an id — the caller should fall back to a full re-sort.
    public static func preservingOrder(current: [Paper], fresh: [Paper]) -> [Paper]? {
        guard current.count == fresh.count else { return nil }
        var freshByID: [Int64: Paper] = [:]
        for p in fresh {
            guard let id = p.id else { return nil }
            if freshByID.updateValue(p, forKey: id) != nil { return nil }
        }
        var out: [Paper] = []
        out.reserveCapacity(current.count)
        for p in current {
            guard let id = p.id, let updated = freshByID[id] else { return nil }
            out.append(updated)
        }
        return out
    }
}
