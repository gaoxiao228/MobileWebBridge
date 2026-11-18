import UIKit
import CoreFoundation

/// 返回控件的原生展示方式；未配置时沿用 iOS 的文字返回。
public enum MWBBackButtonStyle: String { case text, arrow, arrowText }
/// 使用平台系统字体，不依赖宿主安装额外字体。
public enum MWBTitleFontWeight: String {
    case regular, medium, semibold, bold
    var value: UIFont.Weight {
        switch self { case .regular: return .regular; case .medium: return .medium
        case .semibold: return .semibold; case .bold: return .bold }
    }
}

/// 新容器的默认外观；不包含标题、显隐或文档操作回调。
public struct MWBNavigationBarAppearance {
    public let color: UIColor?
    public let titleColor: UIColor?
    public let buttonColor: UIColor?
    public let backButtonStyle: MWBBackButtonStyle?
    public let backButtonText: String?
    public let separatorVisible: Bool?
    public let separatorColor: UIColor?
    public let titleFontSize: CGFloat?
    public let titleFontWeight: MWBTitleFontWeight?
    public let buttonFontSize: CGFloat?
    /// iOS 26 起控制导航按钮的系统玻璃背景；nil 保留系统样式。
    public let buttonBackgroundVisible: Bool?

    public init(color: UIColor? = nil, titleColor: UIColor? = nil, buttonColor: UIColor? = nil,
                backButtonStyle: MWBBackButtonStyle? = nil, backButtonText: String? = nil,
                separatorVisible: Bool? = nil, separatorColor: UIColor? = nil,
                titleFontSize: CGFloat? = nil, titleFontWeight: MWBTitleFontWeight? = nil,
                buttonFontSize: CGFloat? = nil, buttonBackgroundVisible: Bool? = nil) {
        precondition(titleFontSize.map { $0.isFinite && $0 > 0 && $0 <= 32 } ?? true)
        precondition(buttonFontSize.map { $0.isFinite && $0 > 0 && $0 <= 28 } ?? true)
        precondition(backButtonText.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? true)
        self.color = color; self.titleColor = titleColor; self.buttonColor = buttonColor
        self.backButtonStyle = backButtonStyle; self.backButtonText = backButtonText
        self.separatorVisible = separatorVisible; self.separatorColor = separatorColor
        self.titleFontSize = titleFontSize; self.titleFontWeight = titleFontWeight; self.buttonFontSize = buttonFontSize
        self.buttonBackgroundVisible = buttonBackgroundVisible
    }

    var isEmpty: Bool { !hasSharedBarStyle && buttonBackgroundVisible == nil }

    // 按钮底由每个按钮绘制，不属于共享导航栏的外观快照。
    var hasSharedBarStyle: Bool {
        color != nil || titleColor != nil || buttonColor != nil || backButtonStyle != nil || backButtonText != nil
            || separatorVisible != nil || separatorColor != nil || titleFontSize != nil
            || titleFontWeight != nil || buttonFontSize != nil
    }

    /// 缺省字段保留前值，显式按钮色保持独立；未设置时在渲染层回退到标题色。
    func merging(_ next: Self) -> Self {
        .init(color: next.color ?? color, titleColor: next.titleColor ?? titleColor,
              buttonColor: next.buttonColor ?? buttonColor, backButtonStyle: next.backButtonStyle ?? backButtonStyle,
              backButtonText: next.backButtonText ?? backButtonText, separatorVisible: next.separatorVisible ?? separatorVisible,
              separatorColor: next.separatorColor ?? separatorColor, titleFontSize: next.titleFontSize ?? titleFontSize,
              titleFontWeight: next.titleFontWeight ?? titleFontWeight, buttonFontSize: next.buttonFontSize ?? buttonFontSize,
              buttonBackgroundVisible: next.buttonBackgroundVisible ?? buttonBackgroundVisible)
    }

    func buttonFont(traits: UITraitCollection) -> UIFont? {
        buttonFontSize.map { UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: $0), maximumPointSize: 28, compatibleWith: traits) }
    }
}

/// 先完整解析再应用，错误输入不能部分修改页面或创建目标容器。
struct MWBNavigationBarPatch {
    static let keys: Set<String> = ["color", "titleColor", "buttonColor", "backButtonStyle", "backButtonText",
        "showBackButton", "separatorVisible", "separatorColor", "titleFontSize", "titleFontWeight", "buttonFontSize",
        "buttonBackgroundVisible"]
    static let newKeys = keys.subtracting(["color", "titleColor"])
    let appearance: MWBNavigationBarAppearance
    let showBackButton: Bool?
    let enablesIsolation: Bool

    static func parse(_ params: [String: Any], strict: Bool = false) throws -> Self {
        func invalid() -> NSError { NSError(domain: "MWB.NavigationAppearance", code: -1001) }
        func string(_ key: String) throws -> String? {
            guard let value = params[key] else { return nil }
            guard let text = value as? String else { throw invalid() }
            return text
        }
        func boolean(_ key: String) throws -> Bool? {
            guard let value = params[key] else { return nil }
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw invalid() }
            return number.boolValue
        }
        func color(_ key: String) throws -> UIColor? {
            guard params[key] != nil else { return nil }
            // 主题旧字段保留宽松的无效值忽略；新打开参数采用严格校验。
            guard let text = params[key] as? String, let value = UIColor(mwbNavigationHex: text) else {
                if !strict && (key == "color" || key == "titleColor") { return nil }
                throw invalid()
            }
            return value
        }
        func size(_ key: String, max: CGFloat) throws -> CGFloat? {
            guard let value = params[key] else { return nil }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { throw invalid() }
            let result = CGFloat(number.doubleValue)
            guard result.isFinite, result > 0, result <= max else { throw invalid() }
            return result
        }
        let styleText = try string("backButtonStyle")
        let weightText = try string("titleFontWeight")
        let style = styleText.flatMap(MWBBackButtonStyle.init(rawValue:))
        let weight = weightText.flatMap(MWBTitleFontWeight.init(rawValue:))
        guard styleText == nil || style != nil, weightText == nil || weight != nil else { throw invalid() }
        let text = try string("backButtonText")
        guard text == nil || !text!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw invalid() }
        return try .init(appearance: .init(color: color("color"), titleColor: color("titleColor"),
            buttonColor: color("buttonColor"), backButtonStyle: style, backButtonText: text,
            separatorVisible: boolean("separatorVisible"), separatorColor: color("separatorColor"),
            titleFontSize: size("titleFontSize", max: 32), titleFontWeight: weight,
            buttonFontSize: size("buttonFontSize", max: 28), buttonBackgroundVisible: boolean("buttonBackgroundVisible")),
            showBackButton: boolean("showBackButton"),
            enablesIsolation: !Set(params.keys).intersection(strict ? keys : newKeys).isEmpty)
    }
}

extension UIColor {
    convenience init?(mwbNavigationHex text: String) {
        let hex = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard hex.count == 6, hex.allSatisfy({ $0.isASCII && $0.isHexDigit }), let value = UInt32(hex, radix: 16) else { return nil }
        self.init(red: CGFloat((value >> 16) & 255)/255, green: CGFloat((value >> 8) & 255)/255,
                  blue: CGFloat(value & 255)/255, alpha: 1)
    }
}
