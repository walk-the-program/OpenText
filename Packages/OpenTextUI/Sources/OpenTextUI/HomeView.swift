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

/// The window shown on launch, in three columns: New file above Lock, Open with recent files, Convert.
public struct HomeView: View {
    @Binding var quickCreate: QuickCreateState
    @Binding var convert: HomeConvertState
    @Binding var lock: HomeLockState
    let recents: [URL]
    let setupIncomplete: Bool
    let actions: HomeActions
    @State private var dropTargeted = false

    public static let size = CGSize(width: 1240, height: 780)
    private static let pad: CGFloat = 26
    private static let gap: CGFloat = 14
    /// Column widths 1 : 1.2 : 1.
    private static var columns: (CGFloat, CGFloat, CGFloat) {
        let unit = (size.width - pad * 2 - gap * 2) / 3.2
        return (unit, unit * 1.2, unit)
    }

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
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: Brand.Spacing.md) {
                BrandMark(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OpenText").brandHeading(Brand.Fonts.Scale.largeTitle)
                    Text("Open, edit, convert or lock any document.").brandSecondary(13.5)
                }
                Spacer()
                if setupIncomplete {
                    Button("Finish setup", action: actions.onFinishSetup)
                        .buttonStyle(PressableStyle())
                        .font(Brand.Fonts.body(13, weight: .semibold)).foregroundStyle(Brand.Palette.primary)
                        .frame(height: 28).contentShape(Rectangle())
                }
            }
            .padding(.top, 40)        // clear of the traffic lights
            .brandEnter()
            HStack(alignment: .top, spacing: Self.gap) {
                VStack(spacing: Self.gap) {
                    tile("New file", trailing: "⌃⌥N") {
                        QuickCreateView(state: $quickCreate, onCreate: actions.onCreate, onChangeFolder: actions.onChangeFolder, embedded: true)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .brandEnter(delay: 0.04)
                    tile("Lock", trailing: "AES-256") { lockCard }.brandEnter(delay: 0.16)
                }
                .frame(width: Self.columns.0)
                tile("Open", trailing: "⌘O") { openCard }.frame(width: Self.columns.1).brandEnter(delay: 0.08)
                tile("Convert") { convertCard }.frame(width: Self.columns.2).brandEnter(delay: 0.12)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, Self.pad).padding(.bottom, Self.pad)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Brand.Palette.canvas)
    }

    private func tile<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).brandHeading(Brand.Fonts.Scale.title2)
                Spacer()
                if let trailing { Text(trailing).font(Brand.Fonts.body(12, weight: .medium)).foregroundStyle(Brand.Palette.muted) }
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(HoverCard())
    }

    // MARK: Open

    private var openCard: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            HStack(spacing: Brand.Spacing.sm) {
                Button("Open a file…", action: actions.onOpenPanel).buttonStyle(.secondaryAction)
                DropZone(label: "Drop a file", height: Brand.Size.button, targeted: $dropTargeted, onDrop: actions.onDropURLs)
            }
            Text("Recent").brandLabel().padding(.top, 10).padding(.leading, 2)
            if recents.isEmpty {
                Text("Files you open show up here.").font(Brand.Fonts.body(13)).foregroundStyle(Brand.Palette.muted)
                    .padding(.leading, 2)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recents.prefix(9).enumerated()), id: \.offset) { i, url in
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
                Text("Convert to").brandLabel().padding(.top, 8).padding(.leading, 2)
                if convert.targets.isEmpty {
                    Text("OpenText can't convert this kind of file.").font(Brand.Fonts.body(13)).foregroundStyle(Brand.Palette.muted)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(convert.targets, id: \.self) { t in
                                let on = convert.target == t
                                Button { withAnimation(Brand.Motion.settle) { convert.target = t } } label: {
                                    HStack {
                                        Text(ConvertSheet.title(t)).font(Brand.Fonts.body(13.5, weight: on ? .semibold : .medium))
                                            .foregroundStyle(BrandRowText.primary(on))
                                        Spacer()
                                        Text(".\(t)").font(Brand.Fonts.body(12.5)).foregroundStyle(BrandRowText.secondary(on))
                                    }
                                    .padding(.horizontal, 12).frame(height: 38)
                                    .background(BrandRowBackground(selected: on))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityLabel("Convert to \(t)")
                                .accessibilityAddTraits(on ? .isSelected : [])
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                }
            }
            Spacer(minLength: 0)
            StatusLine(status: convert.status, onReveal: actions.onReveal)
            HStack {
                Text("Saved next to the original").font(Brand.Fonts.body(12)).foregroundStyle(Brand.Palette.muted)
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
            if lock.file == nil {
                DropZone(label: "Drop a file to lock", height: nil, targeted: $dropTargeted) { urls in
                    guard let url = urls.first(where: \.isFileURL) else { return false }
                    actions.onLockFile(url); return true
                }
                Text("Pick a file, then a password. The original moves to the Trash.")
                    .font(Brand.Fonts.body(12)).foregroundStyle(Brand.Palette.muted).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            } else {
                FilePicker(file: lock.file, prompt: "Choose a file…", dropLabel: "Drop a file to lock",
                           onPick: actions.onPickLockFile, onDrop: actions.onLockFile)
                SecureField("Password", text: $lock.password).brandField().accessibilityLabel("Password")
                SecureField("Type it again", text: $lock.confirm).brandField().accessibilityLabel("Type it again")
                    .onSubmit { if !lock.busy { actions.onLock() } }
                Text("You need this password, or your recovery key, to open it.")
                    .font(Brand.Fonts.body(12)).foregroundStyle(Brand.Palette.muted).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            StatusLine(status: lock.status, onReveal: actions.onReveal)
            HStack {
                Spacer()
                if lock.file == nil {
                    Button("Choose a file…", action: actions.onPickLockFile).buttonStyle(.secondaryAction)
                } else {
                    Button(lock.busy ? "Locking…" : "Lock", action: actions.onLock)
                        .buttonStyle(.secondaryAction)
                        .disabled(lock.busy || lock.password.isEmpty)
                }
            }
        }
        .brandShake(trigger: lock.status?.isError == true ? lock.status : nil)
    }
}

/// Small type tag in a file row: PDF, MD, PNG…
struct FileTypeTag: View {
    let url: URL
    var selected = false
    var body: some View {
        Text(url.pathExtension.isEmpty ? "FILE" : url.pathExtension.uppercased())
            .font(Brand.Fonts.body(8.5, weight: .semibold)).tracking(0.2)
            .lineLimit(1).minimumScaleFactor(0.7)
            .foregroundStyle(selected ? Brand.Palette.onPrimary : Brand.Palette.muted)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.white.opacity(0.2) : Brand.Palette.well))
            .accessibilityHidden(true)
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
                FileTypeTag(url: file).background(RoundedRectangle(cornerRadius: 8).fill(Brand.Palette.card))
                Text(file.lastPathComponent).font(Brand.Fonts.body(13.5, weight: .semibold)).foregroundStyle(Brand.Palette.ink)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Button("Change", action: onPick)
                    .buttonStyle(PressableStyle())
                    .font(Brand.Fonts.body(13, weight: .semibold)).foregroundStyle(Brand.Palette.primary)
            }
            .padding(.horizontal, 8).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: Brand.Radius.field, style: .continuous).fill(Brand.Palette.priTint))
            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.field, style: .continuous)
                .strokeBorder(targeted ? Brand.Palette.primary : .clear, lineWidth: 1.5))
            .dropDestination(for: URL.self) { urls, _ in pick(urls) } isTargeted: { targeted = $0 }
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        } else {
            VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
                Button(prompt, action: onPick).buttonStyle(.secondaryAction)
                DropZone(label: dropLabel, height: 52, targeted: $targeted) { pick($0) }
            }
        }
    }

    private func pick(_ urls: [URL]) -> Bool {
        guard let url = urls.first(where: \.isFileURL) else { return false }
        withAnimation(Brand.Motion.settle) { onDrop(url) }
        return true
    }
}

/// Well that accepts dropped files. `height` nil fills the space it is given.
struct DropZone: View {
    let label: String
    var height: CGFloat? = 52
    @Binding var targeted: Bool
    let onDrop: ([URL]) -> Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Brand.Radius.field, style: .continuous)
        Group {
            if height == nil {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down").font(.system(size: 17, weight: .medium))
                    Text(label).font(Brand.Fonts.body(13, weight: .medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down").font(.system(size: 12, weight: .semibold))
                    Text(label).font(Brand.Fonts.body(13, weight: .medium))
                }
                .frame(maxWidth: .infinity).frame(height: height)
            }
        }
        .foregroundStyle(targeted ? Brand.Palette.ink : Brand.Palette.muted)
        .background(shape.fill(targeted ? Brand.Palette.priTint : Brand.Palette.well))
        .overlay(shape.strokeBorder(Brand.Palette.primary, lineWidth: targeted ? 2 : 0))
        .scaleEffect(targeted ? 1.015 : 1)
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
                        .font(Brand.Fonts.body(12, weight: .semibold)).foregroundStyle(Brand.Palette.primary)
                }
            }
            .foregroundStyle(status.isError ? Brand.Palette.ink : Brand.Palette.muted)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

/// One recent file: type tag, name and folder, date; hover wash, springy press.
struct RecentRow: View {
    let url: URL
    let onOpen: (URL) -> Void
    @State private var hovering = false
    var body: some View {
        Button { onOpen(url) } label: {
            HStack(spacing: 12) {
                FileTypeTag(url: url)
                VStack(alignment: .leading, spacing: 0) {
                    Text(url.lastPathComponent).font(Brand.Fonts.body(13.5, weight: .semibold))
                        .foregroundStyle(Brand.Palette.ink).lineLimit(1).truncationMode(.middle)
                    Text(url.deletingLastPathComponent().lastPathComponent)
                        .font(Brand.Fonts.body(12)).foregroundStyle(Brand.Palette.muted).lineLimit(1)
                }
                Spacer(minLength: Brand.Spacing.sm)
                if let date = RecentRow.modified(url) {
                    Text(date).font(Brand.Fonts.body(12.5)).foregroundStyle(Brand.Palette.muted).lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44).contentShape(Rectangle())
            .background(BrandRowBackground(selected: false, hovering: hovering))
        }
        .buttonStyle(PressableStyle())
        .brandHover($hovering)
        .accessibilityLabel("Open \(url.lastPathComponent)")
    }

    /// "2 min ago", "Yesterday", "Mon", "Nov 3": when the file last changed.
    static func modified(_ url: URL) -> String? {
        guard let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        if Date().timeIntervalSince(d) < 86_400 { return f.localizedString(for: d, relativeTo: Date()) }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate(Date().timeIntervalSince(d) < 6 * 86_400 ? "EEE" : "MMM d")
        return df.string(from: d)
    }
}
