import AppKit
import SwiftUI

struct AboutView: View {
    @ObservedObject var updateChecker: UpdateChecker

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "关于", subtitle: "版本与更新信息")
            Divider()
            VStack(spacing: 24) {
                identity
                Divider().frame(maxWidth: 460)
                updateStatus
                Divider().frame(maxWidth: 460)
                Link(destination: updateChecker.repositoryURL) {
                    Label("GitHub 开源仓库", systemImage: "link")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        }
        .background(AppPalette.canvas)
        .navigationTitle("关于")
    }

    private var identity: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)
            Text("CodexSkinTool")
                .font(.system(size: 22, weight: .semibold))
            Text("Codex Desktop 一键换肤助手")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            HStack(spacing: 18) {
                metadata("版本", updateChecker.currentVersion)
                metadata("作者", "猫七街")
            }
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updateChecker.state {
        case .idle, .checking:
            status("正在检查更新", icon: "arrow.triangle.2.circlepath") {
                ProgressView().controlSize(.small)
            }
        case .upToDate:
            status("当前已是最新版本", icon: "checkmark.circle.fill", color: AppPalette.success) {
                Button("重新检查") { checkAgain() }
            }
        case .updateAvailable(let version, let url):
            status("发现新版本 \(version)", icon: "arrow.down.circle.fill", color: AppPalette.accent) {
                Link("查看更新", destination: url)
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.accent)
            }
        case .failed(let message):
            status(message, icon: "exclamationmark.circle", color: .secondary) {
                Button("重试") { checkAgain() }
            }
        }
    }

    private func metadata(_ title: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(title).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium)
        }
        .font(.system(size: 12))
    }

    private func status<Action: View>(
        _ title: String,
        icon: String,
        color: Color = .secondary,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(title).font(.system(size: 12, weight: .medium))
            action()
        }
        .frame(minHeight: 28)
    }

    private func checkAgain() {
        Task { await updateChecker.retry() }
    }
}
