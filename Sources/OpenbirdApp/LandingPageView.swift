import SwiftUI

struct LandingPageView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var model: AppModel

    private let featureColumns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 18, alignment: .top)
    ]
    private let highlights = [
        "No account required",
        "No backend required",
        "BYOK models",
        "Stored on your Mac",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 20) {
                        setupProgressCard
                            .frame(width: 320)
                        privacyBoundaryCard
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        setupProgressCard
                        privacyBoundaryCard
                    }
                }

                LazyVGrid(columns: featureColumns, alignment: .leading, spacing: 18) {
                    FeatureCard(
                        symbolName: "list.bullet.rectangle.portrait.fill",
                        title: "See the shape of your day",
                        detail: "Openbird turns captured activity into a local timeline with apps, windows, URLs, and timestamps you can inspect."
                    )
                    FeatureCard(
                        symbolName: "lock.shield.fill",
                        title: "Keep the privacy boundary explicit",
                        detail: "Pause capture, add exclusions, inspect the raw log, and delete data without asking a remote service for permission."
                    )
                    FeatureCard(
                        symbolName: "cpu.fill",
                        title: "Bring your own model",
                        detail: "Ollama, LM Studio, and other OpenAI-compatible endpoints are built in, so local and hosted setups both work."
                    )
                }

                SetupChecklistView(model: model)
            }
            .padding(28)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.12, blue: 0.20),
                            Color(red: 0.11, green: 0.31, blue: 0.29),
                            Color(red: 0.42, green: 0.28, blue: 0.14),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12))

            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 240, height: 240)
                .blur(radius: 40)
                .offset(x: 560, y: -80)

            Circle()
                .fill(Color(red: 0.68, green: 0.89, blue: 0.83).opacity(0.22))
                .frame(width: 280, height: 280)
                .blur(radius: 28)
                .offset(x: -70, y: 130)

            VStack(alignment: .leading, spacing: 22) {
                Text("LOCAL-FIRST MACOS JOURNAL")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.74))

                Text("A local-first journal for your workday.")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Openbird records your activity on-device, turns it into a daily review, and keeps the privacy boundary inspectable from the start.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.84))
                    .fixedSize(horizontal: false, vertical: true)

                heroActions

                LazyVGrid(columns: featureColumns, alignment: .leading, spacing: 10) {
                    ForEach(highlights, id: \.self) { highlight in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text(highlight)
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.12), in: Capsule())
                    }
                }
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, minHeight: 320, alignment: .leading)
    }

    @ViewBuilder
    private var heroActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                heroActionButtons
            }

            VStack(alignment: .leading, spacing: 12) {
                heroActionButtons
            }
        }
    }

    @ViewBuilder
    private var heroActionButtons: some View {
        if model.accessibilityTrusted == false {
            Button {
                model.requestAccessibilityPermission()
            } label: {
                Label("Request Accessibility Access", systemImage: "hand.raised.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Color(red: 0.80, green: 0.93, blue: 0.88))
        }

        if model.activeProvider == nil {
            Button {
                openSettings()
            } label: {
                Label("Open Provider Settings", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }

        Button {
            model.isShowingRawLogInspector = true
        } label: {
            Label("Inspect Raw Log", systemImage: "doc.text.magnifyingglass")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var setupProgressCard: some View {
        LandingSurface {
            VStack(alignment: .leading, spacing: 18) {
                Text("Setup progress")
                    .font(.title3.weight(.semibold))

                Text("\(completedSetupSteps) of 2 required steps complete")
                    .font(.headline)

                HStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { index in
                        Capsule()
                            .fill(index < completedSetupSteps ? Color.accentColor : Color.secondary.opacity(0.16))
                            .frame(height: 10)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    setupStatusRow(
                        title: "Accessibility access",
                        detail: model.accessibilityTrusted
                            ? "Enabled for this copy of Openbird."
                            : "Needed to build your local activity log from the active window tree.",
                        isComplete: model.accessibilityTrusted
                    )

                    setupStatusRow(
                        title: "BYOK provider",
                        detail: model.activeProvider?.name
                            ?? "Choose Ollama, LM Studio, or another OpenAI-compatible endpoint.",
                        isComplete: model.activeProvider != nil
                    )
                }
            }
        }
    }

    private var privacyBoundaryCard: some View {
        LandingSurface {
            VStack(alignment: .leading, spacing: 18) {
                Text("Why Openbird feels trustworthy")
                    .font(.title3.weight(.semibold))

                Text("The app is built around an explicit privacy boundary. Your captured activity stays on your Mac by default, and the app gives you the controls to inspect or delete it.")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 16) {
                    privacyPoint(
                        title: "Local by default",
                        detail: "Captured activity is stored in a local SQLite database instead of a hosted backend."
                    )
                    privacyPoint(
                        title: "Inspectable capture",
                        detail: "You can open the raw log and see the exact evidence used for review generation and chat."
                    )
                    privacyPoint(
                        title: "Explicit control",
                        detail: "Pause capture, configure exclusions, and delete the last hour, day, or everything."
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Local store")
                        .font(.subheadline.weight(.semibold))
                    Text(verbatim: "~/Library/Application Support/Openbird/openbird.sqlite")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var completedSetupSteps: Int {
        (model.accessibilityTrusted ? 1 : 0) + (model.activeProvider != nil ? 1 : 0)
    }

    private func setupStatusRow(
        title: String,
        detail: String,
        isComplete: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isComplete ? .green : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func privacyPoint(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LandingSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.2))
        }
    }
}

private struct FeatureCard: View {
    let symbolName: String
    let title: String
    let detail: String

    var body: some View {
        LandingSurface {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: symbolName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text(title)
                    .font(.headline)

                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
