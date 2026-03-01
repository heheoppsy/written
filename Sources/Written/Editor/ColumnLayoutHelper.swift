import AppKit

struct ColumnLayoutHelper {
    static func insets(for font: NSFont, containerWidth: CGFloat, mode: LayoutMode, columnWidthPercent: Double) -> NSSize {
        switch mode {
        case .fullWidth:
            return NSSize(width: 40, height: 40)

        case .column:
            let fraction = max(0.40, min(0.95, columnWidthPercent / 100.0))
            let columnWidth = containerWidth * fraction
            let horizontalInset = max(40, (containerWidth - columnWidth) / 2)
            return NSSize(width: horizontalInset, height: 40)
        }
    }
}
