import Foundation

/// 使用分组前缀隔离数据，并把有效期与值一同持久化。
final class MWBStorage {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func prefix(for group: String?) -> String {
        let name = group ?? ""
        return "mwb.storage.\(name.count):\(name):"
    }

    private func storageKey(_ key: String, group: String?) -> String {
        prefix(for: group) + key
    }

    @discardableResult
    func set(key: String, value: Any, group: String?, validSeconds: Int?) -> Bool {
        // UserDefaults 只能存 property list；JSON Data 可保留顶层与嵌套的 NSNull。
        guard let encoded = try? JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed) else {
            return false
        }
        var record: [String: Any] = ["json": encoded]
        if let validSeconds {
            record["expiresAt"] = Date().timeIntervalSince1970 + Double(validSeconds)
        }
        defaults.set(record, forKey: storageKey(key, group: group))
        return true
    }

    func get(key: String, group: String?) -> Any? {
        let name = storageKey(key, group: group)
        guard let record = defaults.dictionary(forKey: name) else { return nil }
        if let expiresAt = record["expiresAt"] as? Double,
           Date().timeIntervalSince1970 >= expiresAt {
            defaults.removeObject(forKey: name)
            return nil
        }
        guard let data = record["json"] as? Data else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
    }

    func remove(key: String, group: String?) {
        defaults.removeObject(forKey: storageKey(key, group: group))
    }

    func clear(group: String?) {
        let groupPrefix = prefix(for: group)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(groupPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}

extension MWBBridgeAdapter {
    @objc func setStorageSync(_ arg: Any?) -> Any {
        guard isTrusted else { return MWBResult.failure(-1006, "Untrusted page").dictionary }
        guard let params = arg as? [String: Any], let key = params["key"] as? String,
              !key.isEmpty, let value = params["data"] else {
            return MWBResult.failure(-1001, "Invalid storage parameters").dictionary
        }
        guard storage.set(key: key, value: value, group: params["groupName"] as? String,
                          validSeconds: params["validSecond"] as? Int) else {
            return MWBResult.failure(-1001, "Storage value is not JSON serializable").dictionary
        }
        return NSNull()
    }

    @objc func getStorageSync(_ arg: Any?) -> Any {
        guard isTrusted else { return MWBResult.failure(-1006, "Untrusted page").dictionary }
        guard let params = arg as? [String: Any], let key = params["key"] as? String,
              !key.isEmpty else { return [:] }
        guard let value = storage.get(key: key, group: params["groupName"] as? String) else { return [:] }
        return ["data": value]
    }

    @objc func removeStorageSync(_ arg: Any?) -> Any {
        guard isTrusted else { return MWBResult.failure(-1006, "Untrusted page").dictionary }
        guard let params = arg as? [String: Any], let key = params["key"] as? String,
              !key.isEmpty else { return MWBResult.failure(-1001, "Invalid storage key").dictionary }
        storage.remove(key: key, group: params["groupName"] as? String)
        return NSNull()
    }

    @objc func clearStorageSync(_ arg: Any?) -> Any {
        guard isTrusted else { return MWBResult.failure(-1006, "Untrusted page").dictionary }
        storage.clear(group: (arg as? [String: Any])?["groupName"] as? String)
        return NSNull()
    }
}
