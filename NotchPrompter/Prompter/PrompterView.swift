import SwiftUI

// MARK: - Preference keys

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct LineFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private enum Space {
    static let content = "prompter.content"
}

// MARK: - Root

/// Stable root for the panel's hosting view. Everything below re-reads the
/// controller's observable state, so the hosting view itself never gets rebuilt.
struct PrompterRootView: View {
    let controller: PrompterController

    var body: some View {
        PrompterView(
            settings: controller.settings,
            engine: controller.engine,
            model: controller.model
        )
    }
}

// MARK: - Prompter

struct PrompterView: View {
    var settings: AppSettings
    var engine: ScrollEngine
    var model: ScriptModel

    @State private var dragAnchor: Double?

    private var scrubEnabled: Bool {
        !settings.clickThrough && settings.position != .custom
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                background

                if model.lines.allSatisfy({ $0.text.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    placeholder
                } else {
                    scroller(viewport: geo.size)
                }

                if engine.isCountingDown {
                    countdownOverlay
                }

                progressBar
                    .frame(maxHeight: .infinity, alignment: .bottom)

                DisplayLinkView { dt in
                    engine.tick(dt: dt, speed: settings.scrollSpeed, loop: settings.loopScript)
                }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { engine.viewportHeight = geo.size.height }
            .onChange(of: geo.size.height) { _, height in engine.viewportHeight = height }
        }
        .scaleEffect(x: settings.mirrorText ? -1 : 1, y: 1, anchor: .center)
        .gesture(scrubGesture, including: scrubEnabled ? .gesture : .none)
    }

    // MARK: Pieces

    private var background: some View {
        RoundedRectangle(cornerRadius: settings.cornerRadius, style: .continuous)
            .fill(settings.backgroundColor.opacity(settings.backgroundOpacity))
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

    private func scroller(viewport: CGSize) -> some View {
        VStack(alignment: settings.alignment.horizontal, spacing: settings.lineSpacing) {
            ForEach(model.lines) { line in
                lineView(line)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        // Trailing air so the final line can still scroll up to the reading anchor.
        .padding(.bottom, max(24, viewport.height * 0.55))
        .frame(width: viewport.width, alignment: .top)
        .coordinateSpace(name: Space.content)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(ContentHeightKey.self) { height in
            engine.contentHeight = Double(height)
        }
        .onPreferenceChange(LineFramesKey.self) { frames in
            engine.lineFrames = frames
        }
        .offset(y: -engine.offset)
        .frame(width: viewport.width, height: viewport.height, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: settings.cornerRadius, style: .continuous))
        .mask(settings.fadeEdges ? AnyView(fadeMask) : AnyView(Color.black))
    }

    private func lineView(_ line: ScriptModel.Line) -> some View {
        let raw = Text(line.text.isEmpty ? " " : line.text)
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
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: LineFramesKey.self,
                        value: [line.id: proxy.frame(in: .named(Space.content))]
                    )
                }
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

    private var fadeMask: some View {
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

    private var countdownOverlay: some View {
        ZStack {
            settings.backgroundColor.opacity(0.85)
            Text("\(engine.countdownRemaining)")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(settings.textColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: settings.cornerRadius, style: .continuous))
        .transition(.opacity)
    }

    private var progressBar: some View {
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

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragAnchor == nil { dragAnchor = engine.offset }
                engine.scrub(to: (dragAnchor ?? 0) - Double(value.translation.height))
            }
            .onEnded { _ in dragAnchor = nil }
    }
}
