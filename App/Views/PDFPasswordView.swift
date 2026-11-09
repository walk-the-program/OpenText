import SwiftUI
import OpenTextDesign

/// Shown instead of a blank page when a PDF needs a password to open.
struct PDFPasswordView: View {
    let fileName: String
    let errorMessage: String?
    let onUnlock: (String) -> Void
    @State private var password = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Brand.Palette.canvas
            VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "lock").font(.system(size: 20, weight: .regular)).foregroundStyle(Brand.Palette.ink)
                        .padding(.bottom, 6)
                    Text("This PDF is password-protected").brandHeading(22)
                    Text(fileName).brandBody().foregroundStyle(Brand.Palette.muted).lineLimit(1).truncationMode(.middle)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Password").brandLabel()
                    SecureField("", text: $password).textFieldStyle(.plain).brandField().focused($focused)
                        .onSubmit { if !password.isEmpty { onUnlock(password) } }
                    if let errorMessage {
                        Text(errorMessage).font(Brand.Fonts.body(12, weight: .semibold)).foregroundStyle(Brand.Palette.ink)
                    }
                }
                Button("Open") { onUnlock(password) }.buttonStyle(.primaryAction(showsArrow: false))
                    .keyboardShortcut(.defaultAction).disabled(password.isEmpty)
            }
            .padding(28).frame(width: 360)
            .raisedSurface(radius: Brand.Radius.card, fill: Brand.Palette.surface)
        }
        .onAppear { focused = true }
    }
}
