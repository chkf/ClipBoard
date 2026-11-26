import Foundation

enum HistoryContainer {
    static func url(for bundle: Bundle = .main) throws -> URL {
        // Both processes use the containing app's configuration, including its re-signed bundle ID.
        let host: Bundle?
        if bundle.bundleURL.pathExtension == "appex" {
            let plugins = bundle.bundleURL.deletingLastPathComponent()
            host = Bundle(url: plugins.deletingLastPathComponent())
        } else {
            host = bundle
        }
        let configuration = host ?? bundle
        if configuration.object(forInfoDictionaryKey: "ClipboardPrivateHistory") as? Bool == true {
            throw HistoryError.sharedContainer
        }
        let groups = candidates(
            configured: configuration.object(forInfoDictionaryKey: "ClipboardAppGroup") as? String,
            hostID: host?.bundleIdentifier,
            signerGroups: configuration.object(forInfoDictionaryKey: "ALTAppGroups") as? [String]
        )
        for group in groups {
            if let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
                return directory
            }
        }
        throw HistoryError.sharedContainer
    }

    static func candidates(configured: String?, hostID: String?, signerGroups: [String]?) -> [String] {
        guard let configured, configured.hasPrefix("group."), configured.count > 6 else { return [] }
        var names = [configured]
        if let hostID, !hostID.isEmpty {
            let hostGroup = "group." + hostID
            if hostGroup != configured { names.append(hostGroup) }
        }
        guard let signerGroups else { return names }
        if let exact = names.first(where: signerGroups.contains) { return [exact] }

        // SideStore appends the Apple Team ID. A profile can also list groups for unrelated apps.
        let prefix = configured + "."
        let remapped = Set(signerGroups.filter { group in
            guard group.hasPrefix(prefix) else { return false }
            let suffix = String(group.dropFirst(prefix.count))
            return suffix.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil
        })
        guard remapped.count == 1, let group = remapped.first else { return [] }
        return [group]
    }
}
