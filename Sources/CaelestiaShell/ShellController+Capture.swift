import AppKit
import CaelestiaCore

extension ShellController {
    /// Starts the screenshot tool; the result is a toast (thumbnail, where it went). A second
    /// press while the picker is open cancels it.
    public func takeScreenshot(_ mode: CaptureMode) {
        if screenshots.isActive {
            screenshots.cancel()
            return
        }
        screenshots.config = state.config.capture
        screenshots.theme = theme
        screenshots.onFinish = { [weak self] outcome, thumbnail in
            guard let self else { return }
            switch outcome {
            case .cancelled:
                break
            case .failed(let why):
                _ = self.toast(.error, title: "Screenshot failed", message: why, icon: "screenshot_region")
            case .saved(let file, let copied, let size):
                let image = self.state.config.capture.thumbnail ? thumbnail?.path ?? "" : ""
                _ = self.toast(.success, title: "Screenshot taken", message: ScreenshotText.summary(file: file, copied: copied, size: size),
                               icon: "screenshot_region", imagePath: image)
            }
        }
        screenshots.start(mode)
    }
}

/// Toast text for a finished screenshot.
public enum ScreenshotText {
    public static func summary(file: URL?, copied: Bool, size: CGSize) -> String {
        let px = "\(Int(size.width)) × \(Int(size.height))"
        switch (file, copied) {
        case (let f?, true): return "\(px) · copied, saved as \(f.lastPathComponent)"
        case (let f?, false): return "\(px) · saved as \(f.lastPathComponent)"
        case (nil, true): return "\(px) · copied to the clipboard"
        case (nil, false): return "\(px) · not saved (capture.saveToFolder and copyToClipboard are off)"
        }
    }
}
