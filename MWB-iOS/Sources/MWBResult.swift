import Foundation

/// iOS 与 JS 共用的异步结果格式。
struct MWBResult {
    let errCode: Int
    let errorMsg: String?
    let result: Any?

    static func success(_ result: Any? = nil) -> Self {
        Self(errCode: 0, errorMsg: nil, result: result)
    }

    static func failure(_ code: Int, _ message: String) -> Self {
        Self(errCode: code, errorMsg: message, result: nil)
    }

    var dictionary: [String: Any] {
        var value: [String: Any] = ["errCode": errCode]
        if let errorMsg { value["errorMsg"] = errorMsg }
        if let result { value["result"] = result }
        return value
    }

    var jsonString: String {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary),
              let string = String(data: data, encoding: .utf8) else {
            return "{\"errCode\":-1001,\"errorMsg\":\"Invalid native response\"}"
        }
        return string
    }

    static func parse(_ string: String) -> Self? {
        guard let data = string.data(using: .utf8),
              let dictionary = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let errCode = dictionary["errCode"] as? Int else { return nil }
        return Self(errCode: errCode, errorMsg: dictionary["errorMsg"] as? String,
                    result: dictionary["result"])
    }
}
