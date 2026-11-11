import SwiftUI
import OpenTextDesign

/// A short result line under a Home card: a confirmation (with an optional file to show in Finder) or a problem.
public struct HomeStatus: Equatable, Sendable {
    public var message: String
    public var isError: Bool
    public var reveal: URL?
    public init(message: String, isError: Bool = false, reveal: URL? = nil) {
        self.message = message
        self.isError = isError
        self.reveal = reveal
    }
}

/// Home's Convert card: a file, the formats it can become, the chosen one.
public struct HomeConvertState: Equatable, Sendable {
    public var file: URL?
    public var targets: [String] = []
    public var target: String?
    public var busy = false
    public var status: HomeStatus?
    public init() {}
}

/// Home's Lock card: a file and its new password, typed twice.
public struct HomeLockState: Equatable, Sendable {
    public var file: URL?
    public var password = ""
    public var confirm = ""
    public var busy = false
    public var status: HomeStatus?
    public init() {}
}

/// Everything Home asks the app to do. Pure view; the app wires these.
public struct HomeActions {
    public var onCreate: () -> Void = {}
    public var onChangeFolder: () -> Void = {}
    public var onOpenPanel: () -> Void = {}
    public var onOpenURL: (URL) -> Void = { _ in }
    public var onDropURLs: ([URL]) -> Bool = { _ in false }
    public var onFinishSetup: () -> Void = {}
    public var onPickConvertFile: () -> Void = {}
    public var onConvertFile: (URL) -> Void = { _ in }
    public var onConvert: () -> Void = {}
    public var onPickLockFile: () -> Void = {}
    public var onLockFile: (URL) -> Void = { _ in }
    public var onLock: () -> Void = {}
    public var onReveal: (URL) -> Void = { _ in }
    public init() {}
}

/// The window shown on launch: four cards side by side. New file, Open (button, drop, recents), Convert a file,
/// Lock a file.
public struct HomeView: View {
    @Binding var quickCreate: QuickCreateState
    @Binding var convert: HomeConvertState
    @Binding var lock: HomeLockState
    let recents: [URL]
    let setupIncomplete: Bool
    let actions: HomeActions
    @State private var dropTargeted = false

    public static let size = CGSize(width: 1260, height: 560)

    public init(quickCreate: Binding<QuickCreateState>, convert: Binding<HomeConvertState> = .constant(.init()),
                lock: Binding<HomeLockState> = .constant(.init()), recents: [URL] = [], setupIncomplete: Bool = false,
                actions: HomeActions = .init()) {
        _quickCreate = quickCreate
        _convert = convert
        _lock = lock
        self.recents = recents
        self.setupIncomplete = setupIncomplete
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
            HStack(spacing: Brand.Spacing.md) {
                BrandMark(size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenText").brandHeading(Brand.Fonts.Scale.largeTitle)
                    Text("Open, edit, convert or lock any document.").brandSecondary(14)
                }
                Spacer()
                if setupIncomplete {
                    Button("Finish setup", action: actions.onFinishSetup)
                        .buttonStyle(PressableStyle())
                        .font(Brand.Fonts.body(13, weight: .semibold)).underline(true).foregroundStyle(Brand.Palette.primaryText)
                        .frame(height: 28).contentShape(Rectangle())
                }
            }
            .brandEnter()
            HStack(alignment: .top, spacing: Brand.Spacing.lg) {
                card("New file") {
                    QuickCreateView(state: $quickCreate, onCreate: actions.onCreate, onChangeFolder: actions.onChangeFolder, embedded: true)
                }
                .brandEnter(delay: 0.04)
                card("Open") { openCard }.brandEnter(delay: 0.08)
                card("Convert") { convertCard }.brandEnter(delay: 0.12)
                card("Lock") { lockCard }.brandEnter(delay: 0.16)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(Brand.Spacing.xl)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
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

    // MARK: Open

    private var openCard: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            Button("Open a file…", action: actions.onOpenPanel).buttonStyle(.secondaryAction)
            DropZone(label: "Drop a file here", targeted: $dropTargeted, onDrop: actions.onDropURLs)
                .padding(.bottom, Brand.Spacing.xs)
            Text("Recent").brandLabel()
            if recents.isEmpty {
                Text("Files you open show up here.").font(Brand.Fonts.body(13)).foregroundStyle(Brand.Palette.muted)
                    .padding(.top, 2)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recents.prefix(6).enumerated()), id: \.offset) { i, url in
                        RecentRow(url: url, onOpen: actions.onOpenURL).brandEnter(delay: 0.1 + Double(i) * 0.03)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Convert

    private var convertCard: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            FilePicker(file: convert.file, prompt: "Choose a file…", dropLabel: "Drop a file to convert",
                       onPick: actions.onPickConvertFile, onDrop: actions.onConvertFile)
            if convert.file != nil {
                Text("Convert to").brandLabel().padding(.top, Brand.Spacing.xs)
                if convert.targets.isEmpty {
                    Text("OpenText can't convert this kind of file.").font(Brand.Fonts.body(13)).foregroundStyle(Brand.Palette.muted)
                } else {
                    // Every format visible at once: pills in a grid, the chosen one in the selection gradient.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(convert.targets, id: \.self) { t in
                            let on = convert.target == t
                            Button { withAnimation(Brand.Motion.settle) { convert.target = t } } label: {
                                Text(".\(t)").font(Brand.Fonts.body(13, weight: on ? .semibold : .medium))
                                    .foregroundStyle(on ? Brand.Palette.onPrimary : Brand.Palette.ink)
                                    .frame(maxWidth: .infinity).frame(height: 30)
                                    .background(Capsule().fill(on ? AnyShapeStyle(Brand.Palette.selectionGradient) : AnyShapeStyle(Brand.Palette.abFill)))
                                    .overlay(Capsule().inset(by: 0.5).stroke(Brand.Palette.abHair.opacity(on ? 0 : 1), lineWidth: 1))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(PressableStyle())
                            .help(ConvertSheet.title(t))
                            .accessibilityLabel("Convert to \(t)")
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    if let t = convert.target {
                        Text(ConvertSheet.title(t)).font(Brand.Fonts.body(12)).foregroundStyle(Brand.Palette.muted)
                            .contentTransition(.opacity)
                    }
                }
            }
            Spacer(minLength: 0)
            StatusLine(status: convert.status, onReveal: actions.onReveal)
            HStack {
                Spacer()
                Button(convert.busy ? "Converting…" : "Convert", action: actions.onConvert)
                    .buttonStyle(.secondaryAction)
                    .disabled(convert.busy || convert.file == nil || convert.target == nil)
            }
        }
    }

    // MARK: Lock

    private var lockCard: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            FilePicker(file: lock.file, prompt: "Choose a file…", dropLabel: "Drop a file to lock",
                       onPick: actions.onPickLockFile, onDrop: actions.onLockFile)
            if lock.file != nil {
                Text("Password").brandLabel().padding(.top, Brand.Spacing.xs)
                SecureField("Password", text: $lock.password).brandField().accessibilityLabel("Password")
                SecureField("Type it again", text: $lock.confirm).brandField().accessibilityLabel("Type it again")
                    .onSubmit { if !lock.busy { actions.onLock() } }
                Text("The original moves to the Trash. You need this password, or your recovery key, to open it.")
                    .font(Brand.Fonts.body(12)).foregroundStyle(Brand.Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            StatusLine(status: lock.status, onReveal: actions.onReveal)
            HStack {
                Spacer()
                Button(lock.busy ? "Locking…" : "Lock", action: actions.onLock)
                    .buttonStyle(.secondaryAction)
                    .disabled(lock.busy || lock.file == nil || lock.password.isEmpty)
            }
        }
        .brandShake(trigger: lock.status?.isError == true ? lock.status : nil)
    }
}

/// "Choose a file…" plus a drop zone; once a file is chosen, its name with a Change link.
struct FilePicker: View {
    let file: URL?
    let prompt: String
    let dropLabel: String
    let onPick: () -> Void
    let onDrop: (URL) -> Void
    @State private var targeted = false

    var body: some View {
        if let file {
            HStack(spacing: Brand.Spacing.sm) {
                Image(systemName: "doc").font(.system(size: 14)).foregroundStyle(Brand.Palette.primaryText)
                Text(file.lastPathComponent).font(Brand.Fonts.body(13, weight: .semibold)).foregroundStyle(Brand.Palette.ink)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Button("Change", action: onPick)
                    .buttonStyle(PressableStyle())
                    .font(Brand.Fonts.body(12, weight: .semibold)).underline().foregroundStyle(Brand.Palette.primaryText)
            }
            .padding(.horizontal, 10).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: Brand.Radius.field, style: .continuous).fill(Brand.Palette.priTint))
            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.field, style: .continuous)
                .strokeBorder(targeted ? Brand.Palette.primary : .clear, lineWidth: 1.5))
            .dropDestination(for: URL.self) { urls, _ in pick(urls) } isTargeted: { targeted = $0 }
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        } else {
            VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
                Button(prompt, action: onPick).buttonStyle(.secondaryAction)
                DropZone(label: dropLabel, targeted: $targeted) { pick($0) }
            }
        }
    }

    private func pick(_ urls: [URL]) -> Bool {
        guard let url = urls.first(where: \.isFileURL) else { return false }
        withAnimation(Brand.Motion.settle) { onDrop(url) }
        return true
    }
}

/// Dashed well that accepts dropped files.
struct DropZone: View {
    let label: String
    @Binding var targeted: Bool
    let onDrop: ([URL]) -> Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.doc").font(.system(size: 13))
            Text(label).font(Brand.Fonts.body(13, weight: .medium))
        }
        .foregroundStyle(targeted ? Brand.Palette.ink : Brand.Palette.muted)
        .frame(maxWidth: .infinity).frame(height: 48)
        .background(RoundedRectangle(cornerRadius: Brand.Radius.field, style: .continuous)
            .fill(targeted ? Brand.Palette.priTint : Brand.Palette.abFill))
        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.field, style: .continuous)
            .strokeBorder(targeted ? Brand.Palette.primary : Brand.Palette.line,
                          style: StrokeStyle(lineWidth: targeted ? 1.5 : 1, dash: targeted ? [] : [4, 3])))
        .scaleEffect(targeted ? 1.02 : 1)
        .animation(Brand.Motion.press, value: targeted)
        .dropDestination(for: URL.self) { urls, _ in onDrop(urls) } isTargeted: { targeted = $0 }
    }
}

/// A result line: confirmation in muted text with an optional "Show in Finder", or a problem in ink with an icon.
struct StatusLine: View {
    let status: HomeStatus?
    let onReveal: (URL) -> Void

    var body: some View {
        if let status {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: status.isError ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text(status.message).font(Brand.Fonts.body(12, weight: status.isError ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                if let url = status.reveal {
                    Button("Show in Finder") { onReveal(url) }
                        .buttonStyle(PressableStyle())
                        .font(Brand.Fonts.body(12, weight: .semibold)).underline().foregroundStyle(Brand.Palette.primaryText)
                }
            }
            .foregroundStyle(status.isError ? Brand.Palette.ink : Brand.Palette.muted)
            .transition(.move(edge: .bottom).combined(with: .opacity))
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
