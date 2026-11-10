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
                BrandMark(size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenText").brandHeading(Brand.Fonts.Scale.largeTitle)
                    Text("Open, edit, convert or lock any document.").brandSecondary(14)
                }
            }
            .brandEnter()
            HStack(alignment: .top, spacing: Brand.Spacing.lg) {
                card("New file") {
                    QuickCreateView(state: $quickCreate, onCreate: onCreate, onChangeFolder: onChangeFolder, embedded: true)
                }
                .brandEnter(delay: 0.04)
                card("Open") { openCard }
                    .brandEnter(delay: 0.08)
            }
            .frame(maxHeight: .infinity)
            if setupIncomplete {
                Button("Finish setup", action: onFinishSetup)
                    .buttonStyle(PressableStyle())
                    .font(Brand.Fonts.body(13, weight: .semibold)).underline(true).foregroundStyle(Brand.Palette.primaryText)
                    .padding(.horizontal, 6).frame(height: 20)
                    .contentShape(Rectangle())          // the whole link row is clickable, not just the glyphs
            }
        }
        .padding(Brand.Spacing.xl)
        .frame(width: 800, height: 520, alignment: .topLeading)
        .background(Brand.Palette.canvas)
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.md) {
            Text(title).brandHeading(Brand.Fonts.Scale.title2)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(HoverCard())
    }

    private var openCard: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            Button("Open a file…", action: onOpenPanel).buttonStyle(.secondaryAction)
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.doc").font(.system(size: 13))
                Text("Drop a file here").font(Brand.Fonts.body(13, weight: .medium))
            }
                .foregroundStyle(dropTargeted ? Brand.Palette.ink : Brand.Palette.muted)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: Brand.Radius.field, style: .continuous)
                    .fill(dropTargeted ? Brand.Palette.priTint : Brand.Palette.abFill))
                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.field, style: .continuous)
                    .strokeBorder(dropTargeted ? Brand.Palette.primary : Brand.Palette.line,
                                  style: StrokeStyle(lineWidth: dropTargeted ? 1.5 : 1, dash: dropTargeted ? [] : [4, 3])))
                .scaleEffect(dropTargeted ? 1.02 : 1)
                .animation(Brand.Motion.press, value: dropTargeted)
                .dropDestination(for: URL.self) { urls, _ in onDropURLs(urls) } isTargeted: { dropTargeted = $0 }
                .padding(.bottom, Brand.Spacing.xs)
            Text("Recent").brandLabel()
            if recents.isEmpty {
                Text("Files you open show up here.").font(Brand.Fonts.body(13)).foregroundStyle(Brand.Palette.muted)
                    .padding(.top, 2)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recents.prefix(6).enumerated()), id: \.offset) { i, url in
                        RecentRow(url: url, onOpen: onOpenURL).brandEnter(delay: 0.1 + Double(i) * 0.03)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// One recent file: name and folder, hover wash, springy press.
struct RecentRow: View {
    let url: URL
    let onOpen: (URL) -> Void
    @State private var hovering = false
    var body: some View {
                        Button { onOpen(url) } label: {
                            HStack(spacing: Brand.Spacing.sm) {
                                Text(url.lastPathComponent).font(Brand.Fonts.body(13, weight: .medium))
                                    .foregroundStyle(Brand.Palette.ink).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: Brand.Spacing.sm)
                                Text(url.deletingLastPathComponent().lastPathComponent)
                                    .font(Brand.Fonts.body(12)).foregroundStyle(Brand.Palette.muted)
                                    .lineLimit(1).truncationMode(.tail).layoutPriority(-1)
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 30).contentShape(Rectangle())
                            .background(BrandRowBackground(selected: false, hovering: hovering))
                        }
                        .buttonStyle(PressableStyle())
                        .brandHover($hovering)
                        .accessibilityLabel("Open \(url.lastPathComponent)")
    }
}
