import SwiftUI

/// Mirrors the Security section of System Settings › Privacy & Security —
/// same sentence, same button, without the trip through Settings.
struct PopoverView: View {
    @ObservedObject var store: BlockedAppStore
    var onChooseApp: () -> Void
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if store.apps.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(store.apps.enumerated()), id: \.element.id) { index, app in
                            if index > 0 { Divider().padding(.leading, 56) }
                            row(for: app)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            if let error = store.lastError {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            footer
        }
        .frame(width: 400)
    }

    private var header: some View {
        HStack {
            Text("Security").font(.headline)
            if store.isScanning {
                ProgressView().controlSize(.small).padding(.leading, 2)
            }
            Spacer()
            Button(action: { store.scan() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Scan again")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Nothing is blocked").font(.subheadline).fontWeight(.medium)
            Text("Drag an app onto the menu bar icon to unblock it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    private func row(for app: BlockedApp) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text("“\(app.name)” was blocked to protect your Mac.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                let provenance = app.provenanceLine
                if !provenance.isEmpty {
                    Text(provenance).font(.caption).foregroundStyle(.secondary)
                }

                Button("Open Anyway") { store.openAnyway(app) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button("Unblock an App…", action: onChooseApp).buttonStyle(.link)
            Spacer()
            Menu {
                Button("Open Privacy & Security…", action: onOpenSettings)
                Toggle("Launch at Login", isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { LoginItem.setEnabled($0) }
                ))
                Divider()
                Button("Quit Open Anyway", action: onQuit)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
