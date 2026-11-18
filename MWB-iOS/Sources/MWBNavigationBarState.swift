import UIKit
import ObjectiveC

/// 真实外观快照按容器保存，避免共享导航栏被父页或离屏准备页覆盖。
struct MWBNavigationBarSnapshot {
    var hidden: Bool
    var backgroundColor: UIColor?
    var titleTextAttributes: [NSAttributedString.Key: Any]?
    var tintColor: UIColor?
    var standard: UINavigationBarAppearance
    var scroll: UINavigationBarAppearance?
    var compact: UINavigationBarAppearance?
    var compactScroll: UINavigationBarAppearance?

    init(_ navigation: UINavigationController) {
        let bar = navigation.navigationBar
        hidden = navigation.isNavigationBarHidden; backgroundColor = bar.backgroundColor
        titleTextAttributes = bar.titleTextAttributes; tintColor = bar.tintColor
        standard = bar.standardAppearance.copy(); scroll = bar.scrollEdgeAppearance?.copy()
        compact = bar.compactAppearance?.copy(); compactScroll = bar.compactScrollEdgeAppearance?.copy()
    }

    func restore(_ navigation: UINavigationController) {
        let bar = navigation.navigationBar
        bar.backgroundColor = backgroundColor; bar.titleTextAttributes = titleTextAttributes; bar.tintColor = tintColor
        bar.standardAppearance = standard.copy(); bar.scrollEdgeAppearance = scroll?.copy()
        bar.compactAppearance = compact?.copy(); bar.compactScrollEdgeAppearance = compactScroll?.copy()
        navigation.setNavigationBarHidden(hidden, animated: false)
    }

    mutating func apply(_ style: MWBNavigationBarAppearance, traits: UITraitCollection) {
        guard !style.isEmpty else { return }
        func update(_ original: UINavigationBarAppearance) -> UINavigationBarAppearance {
            let result = original.copy()
            if let color = style.color {
                let titles = result.titleTextAttributes
                let buttons = result.buttonAppearance.copy()
                let shadow = result.shadowColor
                let shadowImage = result.shadowImage
                result.configureWithOpaqueBackground()
                result.backgroundColor = color; result.titleTextAttributes = titles
                result.buttonAppearance = buttons; result.shadowColor = shadow; result.shadowImage = shadowImage
            }
            if let color = style.titleColor { result.titleTextAttributes[.foregroundColor] = color }
            if style.titleFontSize != nil || style.titleFontWeight != nil {
                let font = UIFont.systemFont(ofSize: style.titleFontSize ?? 17,
                    weight: style.titleFontWeight?.value ?? .semibold)
                result.titleTextAttributes[.font] = UIFontMetrics(forTextStyle: .headline).scaledFont(
                    for: font, maximumPointSize: 32, compatibleWith: traits)
            }
            // 颜色字段不改变宿主用透明色或空图片表达的隐藏状态。
            // UIKit 可将透明色归一为 nil；nil 颜色也代表无默认阴影。
            let image = result.shadowImage
            let opaqueImage = image != nil && image?.size != .zero && image?.renderingMode != .alwaysTemplate
            let hiddenShadow = image?.size == .zero
                || (!opaqueImage && (result.shadowColor?.resolvedColor(with: traits).cgColor.alpha ?? 0) == 0)
            if let color = style.separatorColor, !hiddenShadow { result.shadowColor = color }
            if let visible = style.separatorVisible {
                result.shadowColor = visible ? (style.separatorColor ?? .separator) : .clear
                result.shadowImage = nil
            }
            if let font = style.buttonFont(traits: traits) {
                for appearance in [result.buttonAppearance, result.doneButtonAppearance, result.backButtonAppearance] {
                    for state in [appearance.normal, appearance.highlighted, appearance.disabled, appearance.focused] {
                        state.titleTextAttributes[.font] = font
                    }
                }
            }
            return result
        }
        standard = update(standard)
        scroll = update(scroll ?? standard); compact = update(compact ?? standard)
        compactScroll = update(compactScroll ?? compact ?? standard)
        if let color = style.color { backgroundColor = color }
        if let color = style.buttonColor ?? style.titleColor { tintColor = color }
        titleTextAttributes = standard.titleTextAttributes
    }
}

/// 基线归 UINavigationController 生命周期所有；两个宿主不能共享默认或隔离标志。
final class MWBNavigationHostState: NSObject {
    let baseline: MWBNavigationBarSnapshot
    var isolated = false
    init(_ navigation: UINavigationController) { baseline = .init(navigation) }
}
private var mwbNavigationStateKey: UInt8 = 0
extension UINavigationController {
    var mwbNavigationState: MWBNavigationHostState {
        if let state = objc_getAssociatedObject(self, &mwbNavigationStateKey) as? MWBNavigationHostState { return state }
        let state = MWBNavigationHostState(self)
        objc_setAssociatedObject(self, &mwbNavigationStateKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return state
    }
}
