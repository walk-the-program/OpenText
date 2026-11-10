import SwiftUI
import OpenTextDesign

/// The window shown on launch: start a new file, or open one (button, drop, recent). Pure view; the app wires the callbacks.
public struct HomeView: View {
    @Binding var quickCreate: QuickCreateState
    let recents: [URL]
    let setupIncomplete: Bool
    let onCreate: () -> Void
    let onChangeFolder: () -> Void
    let onOpenPanel: () -> Void
    let onOpenURL: (URL) -> Void
    let onDropURLs: ([URL]) -> Bool
    let onFinishSetup: () -> Void
    @State private var dropTargeted = false

    public init(quickCreate: Binding<QuickCreateState>, recents: [URL] = [], setupIncomplete: Bool = false,
                onCreate: @escaping () -> Void = {}, onChangeFolder: @escaping () -> Void = {},
                onOpenPanel: @escaping () -> Void = {}, onOpenURL: @escaping (URL) -> Void = { _ in },
                onDropURLs: @escaping ([URL]) -> Bool = { _ in false}, onFinishSetup: @escaping () -> Void = {}) {
        _quickCreate = quickCreate
        self.recents = recents
        self.setupIncomplete = setupIncomplete
        self.onCreate = onCreate
        self.onChangeFolder = onChangeFolder
        self.onOpenPanel = onOpenPanel
        self.onOpenURL = onOpenURL
        self.onDropURLs = onDropURLs
        self.onFinishSetup = onFinishSetup
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
            HStack(spacing: Brand.Spacing.md) {
                BrandMark(size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenText").brandHeading(22)
                    Text("Open, edit, convert or lock any document.").brandBody().foregroundStyle(Brand.Palette.muted)
                }
            }
            HStack(alignment: .top, spacing: Brand.Spacing.lg) {
                card("New file") {
                    QuickCreateView(state: $quickCreate, onCreate: onCreate, onChangeFolder: onChangeFolder, embedded: true)
                }
                card("Open") { openCard }
            }
            .frame(maxHeight: .infinity)
            if setupIncomplete {
                Button("Finish setup", action: onFinishSetup)
                    .buttonStyle(.plain)
                    .font(Brand.Fonts.body(13, weight: .semibold)).underline(true).foregroundStyle(Brand.Palette.ink)
                    .padding(.horizontal, 6).frame(height: 20)
                    .contentShape(Rectangle())          // the whole link row is clickable, not just the glyphs
            }
        }
        .padding(Brand.Spacing.xl)
        .frame(width: 760, height: 480, alignment: .topLeading)
        .background(Brand.Palette.canvas)
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.md) {
            Text(title).brandHeading(17)
            content()
        }
        .padding(Brand.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .raisedSurface(radius: Brand.Radius.card, fill: Brand.Palette.surface)
    }

    private var openCard: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            Button("Open a file…", action: onOpenPanel).buttonStyle(.secondaryAction)
            Text("Drop a file here").font(Brand.Fonts.body(13, weight: .medium)).foregroundStyle(Brand.Palette.muted)
                .frame(maxWidth: .infinity).frame(height: 44)
                .recessedSurface(radius: Brand.Radius.md)
                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md, style: .continuous)
                    .stroke(Brand.Palette.ink, lineWidth: dropTargeted ? 1.5 : 0))
                .dropDestination(for: URL.self) { urls, _ in onDropURLs(urls) } isTargeted: { dropTargeted = $0 }
                .padding(.bottom, Brand.Spacing.xs)
            Text("Recent").brandLabel()
            if recents.isEmpty {
                Text("Files you open show up here.").font(Brand.Fonts.body(13)).foregroundStyle(Brand.Palette.muted)
                    .padding(.top, 2)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recents.prefix(6).enumerated()), id: \.offset) { i, url in
                        if i > 0 { Rectangle().fill(Brand.Palette.line).frame(height: 1) }
                        Button { onOpenURL(url) } label: {
                            HStack(spacing: Brand.Spacing.sm) {
                                Text(url.lastPathComponent).font(Brand.Fonts.body(13, weight: .medium))
                                    .foregroundStyle(Brand.Palette.ink).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: Brand.Spacing.sm)
                                Text(url.deletingLastPathComponent().lastPathComponent)
                                    .font(Brand.Fonts.body(12)).foregroundStyle(Brand.Palette.muted)
                                    .lineLimit(1).truncationMode(.tail).layoutPriority(-1)
                            }
                            .frame(height: 24).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(url.lastPathComponent)")
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
