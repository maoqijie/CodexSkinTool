import SwiftUI

struct AppSidebar: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        List(selection: $model.selectedSection) {
            Label("换肤", systemImage: "paintbrush")
                .tag(AppSection.themes)
            Label("设置", systemImage: "slider.horizontal.3")
                .tag(AppSection.settings)
            Label {
                HStack {
                    Text("关于")
                    Spacer()
                    if case .updateAvailable = updateChecker.state {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(AppPalette.accent)
                            .accessibilityLabel("有新版本")
                    }
                }
            } icon: {
                Image(systemName: "info.circle")
            }
            .tag(AppSection.about)
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 176, ideal: 188, max: 210)
        .navigationTitle("Codex 换肤")
        .safeAreaInset(edge: .bottom) { statusBar }
    }

    private var statusBar: some View {
        VStack(spacing: 8) {
            Divider()
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.status.title)
                        .font(.system(size: 12, weight: .medium))
                    Text(model.status.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("刷新状态")
                .accessibilityLabel("刷新 Codex 状态")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(.bar)
    }

    private var statusColor: Color {
        guard model.status.app.isInstalled else { return .red }
        return model.status.app.isRunning ? AppPalette.success : .secondary
    }
}
