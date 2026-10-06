import AppKit

@MainActor
public enum AppLogo {
    public static let image: NSImage? = {
        // Try Bundle resources first
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        // Try relative development paths
        let fallbackPaths = [
            "Resources/AppIcon.png",
            "assets/icon.png",
            "assets/icon.jpg"
        ]
        for path in fallbackPaths {
            if let img = NSImage(contentsOfFile: path) {
                return img
            }
        }
        return NSImage(named: NSImage.Name("AppIcon"))
    }()

    public static let menuBarColorIcon: NSImage? = {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = false
            return img
        }
        if let img = NSImage(contentsOfFile: "Resources/MenuBarIcon.png") {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = false
            return img
        }
        if let master = image {
            let size = NSSize(width: 18, height: 18)
            let scaled = NSImage(size: size)
            scaled.lockFocus()
            let clip = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: 17, height: 17), xRadius: 4, yRadius: 4)
            clip.addClip()
            master.draw(in: NSRect(origin: .zero, size: size))
            scaled.unlockFocus()
            scaled.isTemplate = false
            return scaled
        }
        return nil
    }()

    public static let menuBarTemplateIcon: NSImage? = {
        if let url = Bundle.main.url(forResource: "MenuBarTemplate", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            return img
        }
        if let img = NSImage(contentsOfFile: "Resources/MenuBarTemplate.png") {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            return img
        }
        return nil
    }()
}
