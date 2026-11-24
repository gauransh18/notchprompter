import AppKit
import SwiftUI

// MARK: - Root

/// Stable root for the panel's hosting view. Everything below re-reads the
/// controller's observable state, so the hosting view itself never gets rebuilt.
struct PrompterRootView: View {
    let controller: PrompterController

    var body: some View {
        PrompterView(controller: controller)
    }
}

// MARK: - Prompter

/// Layout shell. Deliberately reads nothing that changes every frame: the scroll
/// offset and progress live in their own small views, so a playing script only
/// re-renders those, never the column of text.
struct PrompterView: View {
    let controller: PrompterController

    @State private var dragAnchor: Double?

    private var settings: AppSettings { controller.settings }
    private var engine: ScrollEngine { controller.engine }

    private var scrubEnabled: Bool {
        !settings.clickThrough && settings.position != .custom
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: settings.cornerRadius, style: .continuous)
                    .fill(settings.backgroundColor.opacity(settings.backgroundOpacity))

                if controller.model.isBlank {
                    placeholder
                } else {
                    ScrollingScript(controller: controller, viewport: geo.size)
                        .mask(settings.fadeEdges ? AnyView(FadeMask()) : AnyView(Color.black))
                }

                CountdownOverlay(settings: settings, engine: engine)

                ProgressBar(settings: settings, engine: engine)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                if let hud = controller.hud {
                    HUDView(message: hud, settings: settings)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                        .id(hud.id)
                }

                DisplayLinkView { [settings, engine] dt in
                    engine.tick(dt: dt, speed: settings.scrollSpeed, loop: settings.loopScript)
                }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.16), value: controller.hud)
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { engine.viewportHeight = geo.size.height }
            .onChange(of: geo.size.height) { _, height in engine.viewportHeight = height }
        }
        .scaleEffect(x: settings.mirrorText ? -1 : 1, y: 1, anchor: .center)
        .gesture(scrubGesture, including: scrubEnabled ? .gesture : .none)
    }

    private var placeholder: some View {
        VStack(spacing: 4) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 18, weight: .medium))
            Text("Add your script in Settings")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(settings.textColor.opacity(0.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragAnchor == nil { dragAnchor = engine.offset }
                engine.scrub(to: (dragAnchor ?? 0) - Double(value.translation.height))
            }
            .onEnded { _ in dragAnchor = nil }
    }
}

// MARK: - Scrolling

/// The only view that reads `engine.offset`, so its body runs every frame while the
/// script moves. It hands the offset to `ScrollLayerHost`, which moves the text with
/// a Core Animation transform: SwiftUI never re-lays-out or re-renders the column
/// for a scroll step, however long the script is.
private struct ScrollingScript: NSViewRepresentable {
    let controller: PrompterController
    let viewport: CGSize

    private var settings: AppSettings { controller.settings }

    func makeNSView(context: Context) -> ScrollLayerHost {
        ScrollLayerHost(root: ScriptColumn(controller: controller, viewport: viewport))
    }

    func updateNSView(_ host: ScrollLayerHost, context: Context) {
        host.update(
            viewport: viewport,
            offset: controller.engine.offset,
            cornerRadius: settings.cornerRadius
        ) {
            ScriptColumn(controller: controller, viewport: viewport)
        }
    }
}

final class ScrollLayerHost: NSView {
    private let hosting: NSHostingView<ScriptColumn>
    private var viewport: CGSize

    fileprivate init(root: ScriptColumn) {
        hosting = NSHostingView(rootView: root)
        viewport = root.viewport
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = true

        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var isFlipped: Bool { true }

    /// Mouse and scroll input belongs to the panel's own gestures, not the text.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    fileprivate func update(
        viewport: CGSize,
        offset: Double,
        cornerRadius: CGFloat,
        root: () -> ScriptColumn
    ) {
        if viewport != self.viewport {
            self.viewport = viewport
            hosting.rootView = root()
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.sublayerTransform = CATransform3DMakeTranslation(0, CGFloat(-offset), 0)
        CATransaction.commit()
    }
}

struct ScriptColumn: View {
    let controller: PrompterController
    let viewport: CGSize

    private var settings: AppSettings { controller.settings }
    private var engine: ScrollEngine { controller.engine }

    private static let topPadding: CGFloat = 10

    var body: some View {
        // Trailing air so the final line can still scroll up to the reading anchor.
        let bottomPadding = max(24, viewport.height * 0.55)

        let layout = LineStack(spacing: settings.lineSpacing, padding: Self.topPadding + bottomPadding) { [engine] frames, height in
            let top = Self.topPadding
            engine.lineFrames = Dictionary(
                uniqueKeysWithValues: frames.enumerated().map { ($0.offset, $0.element.offsetBy(dx: 0, dy: top)) }
            )
            engine.contentHeight = Double(height)
        }

        layout {
            ForEach(controller.model.lines) { line in
                lineView(line)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, Self.topPadding)
        .padding(.bottom, bottomPadding)
        .frame(width: viewport.width, alignment: .top)
    }

    private func lineView(_ line: ScriptModel.Line) -> some View {
        let raw = line.styledText.map { Text($0) } ?? Text(line.text.isEmpty ? " " : line.text)
        let styled = line.isDirection ? raw.italic() : raw

        return styled
            .font(settings.font)
            .tracking(settings.fontStyle.tracking)
            .lineSpacing(settings.lineSpacing)
            .multilineTextAlignment(settings.alignment.textAlignment)
            .foregroundStyle(color(for: line))
            .fixedSize(horizontal: false, vertical: true)
            .frame(
                maxWidth: .infinity,
                alignment: Alignment(horizontal: settings.alignment.horizontal, vertical: .top)
            )
    }

    private func color(for line: ScriptModel.Line) -> Color {
        if line.isDirection {
            return settings.textColor.opacity(0.45)
        }
        if let spoken = engine.spokenLine {
            if line.id == spoken { return settings.highlightColor }
            if settings.dimUnreadLines { return settings.textColor.opacity(line.id < spoken ? 0.35 : 0.65) }
        }
        return settings.textColor
    }
}

/// A vertical stack that tells the scroll engine where every line landed.
///
/// Per-line `GeometryReader`s (or `onGeometryChange`) re-evaluate on every frame
/// while the column scrolls, because their transform changes. A layout's
/// `placeSubviews` runs only when sizes actually change, so line positions cost
/// nothing during playback. Line ids are their index, so frames are reported in order.
private struct LineStack: Layout {
    var spacing: CGFloat
    /// Vertical padding around the stack, folded into the reported content height.
    var padding: CGFloat
    /// Line frames relative to the stack, and the full scrollable height.
    var onLayout: @MainActor ([CGRect], CGFloat) -> Void

    struct Cache {
        var reported: [CGRect]?
        var reportedHeight: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: total(heights))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let child = ProposedViewSize(width: bounds.width, height: nil)
        var y: CGFloat = 0
        var frames: [CGRect] = []
        frames.reserveCapacity(subviews.count)

        for subview in subviews {
            let height = subview.sizeThatFits(child).height
            subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY + y), proposal: child)
            frames.append(CGRect(x: 0, y: y, width: bounds.width, height: height))
            y += height + spacing
        }

        let height = total(frames.map(\.height)) + padding
        guard frames != cache.reported || height != cache.reportedHeight else { return }
        cache.reported = frames
        cache.reportedHeight = height
        // Never mutate observable state in the middle of a layout pass.
        DispatchQueue.main.async { onLayout(frames, height) }
    }

    private func total(_ heights: [CGFloat]) -> CGFloat {
        heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1))
    }
}

private struct FadeMask: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.10),
                .init(color: .black, location: 0.86),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Overlays

private struct CountdownOverlay: View {
    let settings: AppSettings
    let engine: ScrollEngine

    var body: some View {
        if engine.isCountingDown {
            ZStack {
                settings.backgroundColor.opacity(0.85)
                Text("\(engine.countdownRemaining)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(settings.textColor)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: engine.countdownRemaining)
            }
            .clipShape(RoundedRectangle(cornerRadius: settings.cornerRadius, style: .continuous))
            .transition(.opacity)
        }
    }
}

private struct ProgressBar: View {
    let settings: AppSettings
    let engine: ScrollEngine

    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(settings.highlightColor.opacity(0.85))
                .frame(width: proxy.size.width * engine.progress, height: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 2)
        .opacity(engine.progress > 0 ? 1 : 0)
        .allowsHitTesting(false)
    }
}

private struct HUDView: View {
    let message: PrompterController.HUDMessage
    let settings: AppSettings

    var body: some View {
        Label(message.text, systemImage: message.symbol)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(settings.textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(settings.backgroundColor.opacity(0.9))
                    .overlay(Capsule(style: .continuous).strokeBorder(settings.textColor.opacity(0.18)))
            )
            .allowsHitTesting(false)
    }
}
