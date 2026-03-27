import SwiftUI

struct SetupChecklistView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Finish setup")
                    .font(.title2.weight(.semibold))
                Text("Openbird starts in Today now. Turn on capture and connect a provider here when you are ready.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                permissionRow(
                    title: "Accessibility access",
                    description: "Needed to read the active window tree and build the local activity log.",
                    isComplete: model.accessibilityTrusted
                ) {
                    HStack(spacing: 12) {
                        Button("Request Accessibility Access") {
                            model.requestAccessibilityPermission()
                        }
                        Button("Open Accessibility Settings") {
                            model.openAccessibilitySettings()
                        }
                    }
                }
                permissionRow(
                    title: "BYOK provider",
                    description: "Needed for journal generation and chat. Local and hosted providers are built in.",
                    isComplete: model.activeProvider != nil
                ) {
                    Button("Open Provider Settings") {
                        model.selection = .settings
                    }
                }
            }
            .padding(24)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func permissionRow<Actions: View>(
        title: String,
        description: String,
        isComplete: Bool,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? .green : .secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
                if let path = model.accessibilityManualGrantPath, isComplete == false {
                    Text("If you launched from source, macOS may show this as \(model.accessibilityTargetName) instead of Openbird. If it does not appear automatically, use the + button in Accessibility settings and add:")
                        .foregroundStyle(.secondary)
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                actions()
                    .padding(.top, 8)
            }
        }
    }
}
