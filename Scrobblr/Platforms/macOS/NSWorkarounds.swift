//
//  WindowAccessor.swift
//  Scroblrr
//
//  Created by Renan Martins on 6/18/26.
//

#if os(macOS)
import AppKit
import SwiftUI

// 1. NSHostingView subclass that zeroes its own safe area
final class NSHostingViewIgnoringSafeArea<T: View>: NSHostingView<T> {
    required init(rootView: T) {
        super.init(rootView: rootView)
        addLayoutGuide(layoutGuide)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: layoutGuide.leadingAnchor),
            topAnchor.constraint(equalTo: layoutGuide.topAnchor),
            trailingAnchor.constraint(equalTo: layoutGuide.trailingAnchor),
            bottomAnchor.constraint(equalTo: layoutGuide.bottomAnchor)
        ])
    }

    override func viewDidMoveToWindow() {
        window?.alphaValue = 0  // hide until layout settles
        super.viewDidMoveToWindow()
    }

    private lazy var layoutGuide = NSLayoutGuide()
    required init?(coder: NSCoder) { fatalError() }

    override var safeAreaRect: NSRect { frame }
    override var safeAreaInsets: NSEdgeInsets { .init(top: 0, left: 0, bottom: 0, right: 0) }
    override var safeAreaLayoutGuide: NSLayoutGuide { layoutGuide }
    override var additionalSafeAreaInsets: NSEdgeInsets {
        get { .init(top: 0, left: 0, bottom: 0, right: 0) }
        set {}
    }
}

// 2. NSViewRepresentable that IS the hosting view (not a proxy)
struct ToolbarAwareHostingView<Content: View>: NSViewRepresentable {
    @Binding var topPadding: CGFloat
    let content: () -> Content

    func makeNSView(context: Context) -> NSView {
        let view = NSHostingViewIgnoringSafeArea(rootView: content())
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let titlebarHeight = window.frame.height - window.contentLayoutRect.height
            topPadding = -titlebarHeight
            window.isMovableByWindowBackground = true
            window.alphaValue = 1
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// 3. Modifier to wire it up
struct HideTitlebarModifier: ViewModifier {
    @State private var topPadding: CGFloat = 0

    func body(content: Content) -> some View {
        ToolbarAwareHostingView(topPadding: $topPadding) { content }
            .padding(.top, topPadding)  // negative padding pulls content up into titlebar
    }
}

extension View {
    func hideTitlebar() -> some View {
        modifier(HideTitlebarModifier())
    }
}
#endif
