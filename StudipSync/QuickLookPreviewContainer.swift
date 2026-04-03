import AppKit
import QuickLookUI
import SwiftUI

struct QuickLookPreviewContainer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        if let view = QLPreviewView(frame: .zero, style: .normal) {
            view.previewItem = url as NSURL
            return view
        }

        let fallback = NSTextField(labelWithString: "Vorschau ist fuer diese Datei nicht verfuegbar.")
        fallback.alignment = .center
        fallback.textColor = .secondaryLabelColor
        return fallback
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? QLPreviewView)?.previewItem = url as NSURL
    }
}
