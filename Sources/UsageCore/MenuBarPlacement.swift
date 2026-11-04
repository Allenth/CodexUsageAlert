import Foundation

public enum MenuBarPlacement {
    public static func replacementPosition(for savedPosition: Double?, screenWidths: [Double]) -> Double? {
        guard let savedPosition,
              let widestScreen = screenWidths.filter({ $0.isFinite && $0 > 0 }).max()
        else { return nil }
        guard !savedPosition.isFinite || savedPosition < 0 || savedPosition > widestScreen
        else { return nil }
        return min(240, widestScreen / 2)
    }
}
