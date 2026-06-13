public enum TagNormalizer {
    public static func normalize(_ raw: String) -> [String] {
        var seen = Set<String>()
        var out = [String]()
        for piece in raw.split(whereSeparator: { $0 == "," || $0 == ";" }) {
            let collapsed = piece.split(whereSeparator: { $0 == " " || $0 == "\t" })
                .joined(separator: " ")
                .lowercased()
            guard !collapsed.isEmpty, !seen.contains(collapsed) else { continue }
            seen.insert(collapsed); out.append(collapsed)
        }
        return out
    }

    public static func normalize(_ list: [String]) -> [String] {
        normalize(list.joined(separator: ","))
    }
}
