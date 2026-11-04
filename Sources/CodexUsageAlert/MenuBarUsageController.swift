import AppKit
import Combine
import SwiftUI
import UsageCore

@MainActor
final class MenuBarUsageController: NSObject {
    private let monitor: UsageMonitor
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var observation: AnyCancellable?

    init(monitor: UsageMonitor) {
        self.monitor = monitor
        super.init()
        statusItem.autosaveName = "Item-0"
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: UsagePopover(monitor: monitor))
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
        }
        update()
        observation = monitor.objectWillChange.sink { [weak self] _ in
            // ObservableObject publishes before mutation; read the resulting values.
            DispatchQueue.main.async { self?.update() }
        }
    }

    private func update() {
        guard let button = statusItem.button else { return }
        let services = monitor.menuServices
        let summary = services.map(\.summary).joined(separator: "\n")
        button.toolTip = summary
        button.setAccessibilityLabel("用量预警，\(summary)")
        button.image = nil
        button.title = ""
        switch monitor.menuBarDisplayStyle {
        case .progressBars:
            button.image = MenuBarProgressImage.make(services: services)
        case .numbers:
            let title = NSMutableAttributedString(string: "")
            for (index, service) in services.enumerated() {
                title.append(NSAttributedString(string: "\(index == 0 ? "" : "  ")\(service.label) \(service.number)",
                    attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                                 .foregroundColor: service.usedPercent == nil ? NSColor.disabledControlTextColor : NSColor.labelColor]))
            }
            button.attributedTitle = title
        case .highest:
            button.attributedTitle = NSAttributedString(
                string: services.compactMap(\.usedPercent).max().map { "\(Int($0.rounded()))%" } ?? "—",
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                             .foregroundColor: NSColor.labelColor])
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

/// A template drawing lets macOS choose contrast for the menu bar, independently
/// of the dashboard's dark appearance. NSImage draws at the display's native scale.
enum MenuBarProgressImage {
    static func make(services: [MenuBarServiceUsage]) -> NSImage {
        let image = NSImage(size: NSSize(width: 58, height: 20), flipped: false) { _ in
            for (index, service) in services.prefix(2).enumerated() {
                let y: CGFloat = index == 0 ? 11 : 1
                let active = service.usedPercent != nil
                let color = NSColor.black.withAlphaComponent(active ? 1 : 0.35)
                (service.label as NSString).draw(at: NSPoint(x: 0, y: y - 1), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                    .foregroundColor: color,
                ])
                let rect = NSRect(x: 12, y: y + 1, width: 45, height: 6)
                // The outline keeps a valid 0% distinct from unavailable data.
                color.setStroke()
                let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 1, yRadius: 1)
                outline.lineWidth = 1
                outline.stroke()
                if active {
                    NSColor.black.setFill()
                    NSBezierPath(rect: NSRect(x: rect.minX + 1, y: rect.minY + 1,
                        width: (rect.width - 2) * service.fraction, height: rect.height - 2)).fill()
                } else {
                    color.setStroke()
                    let dash = NSBezierPath()
                    dash.move(to: NSPoint(x: rect.midX - 3, y: rect.midY))
                    dash.line(to: NSPoint(x: rect.midX + 3, y: rect.midY))
                    dash.lineWidth = 1
                    dash.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = services.map(\.summary).joined(separator: ", ")
        return image
    }
}
