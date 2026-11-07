import UIKit
import WebKit

/// 单次离屏准备：源页持有任务，目标页仅弱引用任务，避免延长页面生命周期。
final class MWBNavigationPreparation {
    private weak var source: MWBWebViewController?
    private let target: MWBWebViewController
    private let sourceRevision: Int
    private var completion: ((MWBResult) -> Void)?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var snapshotRevision: Int?
    private let deadline = ProcessInfo.processInfo.systemUptime + 3
    private let show: (MWBWebViewController) -> Void

    init(source: MWBWebViewController, target: MWBWebViewController,
         show: @escaping (MWBWebViewController) -> Void, completion: @escaping (MWBResult) -> Void) {
        self.source = source
        self.target = target
        sourceRevision = source.documentRevision
        self.show = show
        self.completion = completion
    }

    func start() {
        guard let source, source.canStartPreparedNavigation else { cancel(); return }
        target.navigationPreparation = self
        let timer = Timer(timeInterval: 3, repeats: false) { [weak self] _ in
            self?.finish(.failure(-1002, "Page preparation timed out"))
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in self?.cancel() })
        if let scene = source.view.window?.windowScene {
            observers.append(NotificationCenter.default.addObserver(forName: UIScene.willDeactivateNotification,
                object: scene, queue: .main) { [weak self] _ in self?.cancel() })
        }
        // 使用实际视口完成布局；不把离屏目标插入源页，也不展示快照。
        target.loadViewIfNeeded()
        guard completion != nil else { return }
        target.view.frame = source.view.bounds
        target.view.setNeedsLayout()
        target.view.layoutIfNeeded()
        stateChanged()
    }

    func documentChanged() { snapshotRevision = nil }

    func stateChanged() {
        guard completion != nil else { return }
        switch target.loadState {
        case .failed:
            finish(.failure(-1002, "Page loading failed"))
        case .loaded:
            let revision = target.documentRevision
            guard snapshotRevision != revision, let webView = target.webView else { return }
            guard let source else { cancel(); return }
            snapshotRevision = revision
            // 加载期间可能旋转或分屏；每次绘制都使用当前来源视口。
            let viewport = source.view.bounds.size
            target.view.frame = CGRect(origin: .zero, size: viewport)
            target.view.setNeedsLayout()
            target.view.layoutIfNeeded()
            let config = WKSnapshotConfiguration()
            config.afterScreenUpdates = true
            webView.takeSnapshot(with: config) { [weak self] image, error in
                guard let self, self.completion != nil,
                      self.target.documentRevision == revision, self.target.loadState == .loaded else { return }
                // 主线程宿主回调可能阻塞计时器，成功路径也必须遵守同一总截止时间。
                guard ProcessInfo.processInfo.systemUptime < self.deadline else {
                    self.finish(.failure(-1002, "Page preparation timed out")); return
                }
                guard image != nil, error == nil else {
                    self.finish(.failure(-1002, "Page drawing preparation failed")); return
                }
                guard let source = self.source, source.documentRevision == self.sourceRevision,
                      source.canStartPreparedNavigation else { self.cancel(); return }
                guard source.view.bounds.size == viewport, self.target.view.bounds.size == viewport else {
                    // 快照在途时尺寸变化，旧绘制作废；仍受原总截止时间约束。
                    self.snapshotRevision = nil
                    self.stateChanged()
                    return
                }
                self.finish(.success(), navigate: true)
            }
        default: break
        }
    }

    func cancel(deliverReply: Bool = true) {
        finish(.failure(-1005, "Navigation preparation cancelled"), deliverReply: deliverReply)
    }

    private func finish(_ result: MWBResult, navigate: Bool = false, deliverReply: Bool = true) {
        guard let completion else { return }
        self.completion = nil
        timer?.invalidate(); timer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        target.navigationPreparation = nil
        // 先解除任务再转场，避免源页 willDisappear 取消已经成功的请求。
        if source?.pendingNavigation === self { source?.pendingNavigation = nil }
        if navigate { show(target) } else { target.abandonNavigationPreparation() }
        if deliverReply, source?.documentRevision == sourceRevision { completion(result) }
    }

    deinit {
        timer?.invalidate()
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
