import Foundation
#if canImport(MobileWebBridge)
import MobileWebBridge
#endif

/// 服务由宿主持有和注入；MWB Core 不绑定任何具体网络客户端。
struct ExampleNetworkResponse {
    let status: Int
    let headers: [String: String]
    let body: String
}
protocol ExampleNetworkServing {
    func send(_ request: URLRequest, completion: @escaping (Result<ExampleNetworkResponse, Error>) -> Void) -> () -> Void
}

final class ExampleNetworkPlugin: MWBPlugin {
    private let service: ExampleNetworkServing
    init(service: ExampleNetworkServing) { self.service = service; super.init() }

    @objc(mwb_request:context:responder:)
    func request(_ params: Any?, context: MWBPluginCallContext, responder: MWBPluginResponder) {
        do {
            let request = try ExampleNetworkService.makeRequest(params)
            let cancel = service.send(request) { result in
                switch result {
                case .success(let response):
                    responder.success(["status": response.status, "headers": response.headers, "body": response.body])
                    context.emit("requestFinished", data: ["url": request.url!.absoluteString, "status": response.status])
                case .failure:
                    responder.failure(1001, message: "Network request failed or response exceeded the text limit")
                }
            }
            context.onCancel(cancel)
        } catch { responder.failure(-1102, message: "Expected allowlisted HTTPS GET/POST text request") }
    }
}

/// 宿主允许列表为精确域名，重定向也执行相同校验，禁止降级 HTTP 或转向内网。
final class ExampleNetworkService: ExampleNetworkServing {
    static let allowedHosts: Set<String> = ["example.com", "httpbin.org"]
    static let maxBytes = 1024 * 1024
    private let configuration: URLSessionConfiguration
    init(configuration: URLSessionConfiguration = .ephemeral) { self.configuration = configuration }

    static func allowed(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && allowedHosts.contains(url.host?.lowercased() ?? "")
            && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }
    static func makeRequest(_ params: Any?) throws -> URLRequest {
        guard let params = params as? [String: Any],
              let text = params["url"] as? String, let url = URL(string: text), allowed(url),
              let method = params["method"] as? String, ["GET", "POST"].contains(method),
              params["body"] == nil || (method == "POST" && params["body"] is String),
              params["headers"] == nil || params["headers"] is [String: String] else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body = params["body"] as? String {
            guard body.utf8.count <= maxBytes else { throw URLError(.dataLengthExceedsMaximum) }
            request.httpBody = Data(body.utf8)
        }
        for (key, value) in params["headers"] as? [String: String] ?? [:] {
            guard key.range(of: "^[!#$%&'*+.^_`|~0-9a-zA-Z-]+$", options: .regularExpression) != nil,
                  !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
                throw URLError(.badURL)
            }
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
    func send(_ request: URLRequest, completion: @escaping (Result<ExampleNetworkResponse, Error>) -> Void) -> () -> Void {
        let transfer = ExampleNetworkTransfer(completion: completion)
        let session = URLSession(configuration: configuration, delegate: transfer, delegateQueue: nil)
        let task = session.dataTask(with: request)
        task.resume()
        // task 持有 session；完成后 delegate 会使 session 失效释放所有权。
        return { task.cancel() }
    }
}

/// 流式累计上限防止先下载任意大响应再检查大小；不使用 dataTask completion 的整包缓冲。
private final class ExampleNetworkTransfer: NSObject, URLSessionDataDelegate {
    private let completion: (Result<ExampleNetworkResponse, Error>) -> Void
    private var data = Data()
    private var response: HTTPURLResponse?
    private var policyFailure = false
    init(completion: @escaping (Result<ExampleNetworkResponse, Error>) -> Void) { self.completion = completion }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, ExampleNetworkService.allowed(url),
              ["GET", "POST"].contains(request.httpMethod ?? "GET") else {
            policyFailure = true; completionHandler(nil); task.cancel(); return
        }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse,
              response.expectedContentLength <= Int64(ExampleNetworkService.maxBytes) else {
            policyFailure = true; completionHandler(.cancel); return
        }
        self.response = http
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive bytes: Data) {
        guard data.count <= ExampleNetworkService.maxBytes - bytes.count else {
            policyFailure = true; dataTask.cancel(); return
        }
        data.append(bytes)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { session.finishTasksAndInvalidate() }
        guard error == nil, !policyFailure, let response, let text = String(data: data, encoding: .utf8) else {
            completion(.failure(error ?? URLError(.cannotDecodeContentData))); return
        }
        var headers: [String: String] = [:]
        for (name, value) in response.allHeaderFields { headers[String(describing: name)] = String(describing: value) }
        completion(.success(.init(status: response.statusCode, headers: headers, body: text)))
    }
}
