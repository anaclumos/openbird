import SwiftUI
import OpenbirdKit

struct RawLogInspectorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(filteredEvents) { event in
                HStack(alignment: .top, spacing: 12) {
                    ActivityAppIcon(bundleId: event.bundleId, appName: event.appName)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(OpenbirdDateFormatting.timeString(for: event.startedAt)) – \(OpenbirdDateFormatting.timeString(for: event.endedAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if event.isExcluded {
                                Label("Excluded", systemImage: "eye.slash")
                                    .font(.caption)
                            }
                        }
                        Text(event.appName)
                            .font(.headline)
                        if let detailTitle = event.detailTitle {
                            Text(detailTitle)
                        }
                        if let url = event.url {
                            Text(url)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if event.excerpt.isEmpty == false {
                            Text(event.excerpt)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .navigationTitle("Raw Logs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 540)
    }

    private var filteredEvents: [ActivityEvent] {
        model.rawEvents.filter { event in
            if event.bundleId == "com.apple.loginwindow" || event.appName.lowercased() == "loginwindow" {
                return false
            }

            let hasUsefulText = event.visibleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let hasUsefulURL = (event.url?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            let hasSpecificTitle = (event.detailTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)

            return hasUsefulText || hasUsefulURL || hasSpecificTitle
        }
    }
}
