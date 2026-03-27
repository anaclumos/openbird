import SwiftUI
import OpenbirdKit

struct TodayView: View {
    @ObservedObject var model: AppModel
    @State private var isShowingSupportingEvidence = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                DatePicker("Day", selection: Binding(
                    get: { model.selectedDay },
                    set: { model.selectDay($0) }
                ), displayedComponents: .date)
                .datePickerStyle(.compact)

                Spacer()

                Button("Inspect Evidence") {
                    model.isShowingRawLogInspector = true
                }
                Button("Generate Summary") {
                    model.generateTodayJournal()
                }
                .buttonStyle(.borderedProminent)
            }

            if let journal = model.todayJournal {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if model.needsOnboarding {
                            SetupChecklistView(model: model)
                        }
                        summaryHeader(journal)
                        summaryCard(journal.markdown)

                        if journal.sections.isEmpty == false {
                            DisclosureGroup(isExpanded: $isShowingSupportingEvidence) {
                                VStack(alignment: .leading, spacing: 14) {
                                    ForEach(journal.sections) { section in
                                        sectionCard(section)
                                    }
                                }
                                .padding(.top, 12)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Supporting Evidence")
                                        .font(.headline)
                                    Text("Grouped source material used to generate this summary.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(20)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 20))
                        }
                    }
                    .frame(maxWidth: 860, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    if model.needsOnboarding {
                        SetupChecklistView(model: model)
                    }

                    ContentUnavailableView(
                        "No daily summary yet",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Capture some activity, then generate a clean summary from your local logs.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(28)
        .navigationTitle("Today")
    }

    private func summaryHeader(_ journal: DailyJournal) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Daily Summary")
                .font(.system(size: 30, weight: .semibold))

            HStack(spacing: 10) {
                Label(summaryStatusTitle(for: journal), systemImage: journal.providerID == nil ? "sparkles.slash" : "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(summaryStatusBackground(for: journal), in: Capsule())

                if let providerName = model.providerName(for: journal.providerID) {
                    Text(providerName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Text(summaryStatusDescription(for: journal))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func summaryCard(_ markdown: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            markdownView(markdown)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder
    private func markdownView(_ markdown: String) -> some View {
        if let attributed = try? AttributedString(markdown: markdown) {
            Text(attributed)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(markdown)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryStatusTitle(for journal: DailyJournal) -> String {
        journal.providerID == nil ? "Fallback Summary" : "LLM Summary"
    }

    private func summaryStatusDescription(for journal: DailyJournal) -> String {
        if journal.providerID == nil {
            return "This review used the local fallback formatter. Connect a model in Settings to generate a more polished LLM summary from the same evidence."
        }
        return "Generated from your local activity logs. Openbird keeps the supporting evidence available for inspection."
    }

    private func summaryStatusBackground(for journal: DailyJournal) -> Color {
        journal.providerID == nil ? Color.orange.opacity(0.16) : Color.blue.opacity(0.14)
    }

    private func sectionCard(_ section: JournalSection) -> some View {
        let event = representativeEvent(for: section)

        return HStack(alignment: .top, spacing: 12) {
            ActivityAppIcon(
                bundleId: event?.bundleId,
                appName: event?.appName ?? section.heading,
                size: 30
            )
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("\(section.timeRange) • \(section.heading)")
                    .font(.headline)
                ForEach(section.bullets, id: \.self) { bullet in
                    Text("• \(bullet)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
    }

    private func representativeEvent(for section: JournalSection) -> ActivityEvent? {
        let sourceEventIDs = Set(section.sourceEventIDs)
        return model.rawEvents.first { sourceEventIDs.contains($0.id) }
    }
}
