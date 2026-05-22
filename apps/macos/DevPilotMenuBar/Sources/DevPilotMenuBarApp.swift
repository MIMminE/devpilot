import AppKit
import Combine
import SwiftUI

@main
struct DevPilotMenuBarApp: App {
    @NSApplicationDelegateAdaptor(DevPilotAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            DevPilotSettingsRedirectView {
                appDelegate.runner.openSetupWindow()
            }
        }
    }
}

@MainActor
final class DevPilotAppDelegate: NSObject, NSApplicationDelegate {
    fileprivate let runner = DevPilotRunner()
    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private var pendingSingleClick: DispatchWorkItem?

    func applicationWillFinishLaunching(_ notification: Notification) {
        installDeepLinkHandler()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        installStatusItem()
        bindRunner()
    }

    private func installDeepLinkHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: value) else {
            runner.openLastOutputWindow()
            return
        }
        runner.handleDeepLink(url)
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        guard let button = item.button else { return }
        button.image = statusImage()
        button.toolTip = "DevPilot"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func bindRunner() {
        runner.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)

        runner.$isRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshStatusItem()
            }
            .store(in: &cancellables)
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        button.image = statusImage()
        button.toolTip = "DevPilot - \(runner.status)"
    }

    private func statusImage() -> NSImage? {
        let name = runner.isRunning ? "bolt.circle.fill" : "bolt.circle"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "DevPilot")
        image?.isTemplate = true
        return image
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let clickCount = NSApp.currentEvent?.clickCount ?? 1
        if clickCount >= 2 {
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
            runner.openWorkWindow()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.openMenu()
        }
        pendingSingleClick = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    private func openMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        let status = NSMenuItem(title: runner.status, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(menuItem("작업 대시보드 열기", action: #selector(openDashboard)))
        menu.addItem(menuItem("빠른 작업 메모", action: #selector(openQuickMemo)))
        menu.addItem(menuItem("설정 열기", action: #selector(openSettings)))
        menu.addItem(menuItem("AI 프롬프트 규칙 편집", action: #selector(openReportAgent)))
        menu.addItem(menuItem("설정 폴더 열기", action: #selector(openSupportDirectory)))

        if !runner.lastOutput.isEmpty {
            menu.addItem(.separator())
            menu.addItem(menuItem("마지막 실행 결과 보기", action: #selector(openLastOutput)))
            menu.addItem(menuItem("마지막 실행 결과 복사", action: #selector(copyLastOutput)))
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("종료", action: #selector(quit)))

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openDashboard() {
        runner.openWorkWindow()
    }

    @objc private func openSettings() {
        runner.openSetupWindow()
    }

    @objc private func openQuickMemo() {
        runner.openQuickMemoWindow()
    }

    @objc private func openReportAgent() {
        runner.openReportAgentEditor()
    }

    @objc private func openSupportDirectory() {
        runner.openSupportDirectory()
    }

    @objc private func openLastOutput() {
        runner.openLastOutputWindow()
    }

    @objc private func copyLastOutput() {
        runner.copyLastOutput()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private struct DevPilotSettingsRedirectView: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DevPilot 설정")
                .font(.title2)
                .bold()

            Text("실제 설정은 DevPilot 작업 콘솔과 같은 흐름에서 열립니다.")
                .foregroundStyle(.secondary)

            Button("설정 창 열기", action: openSettings)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 360, alignment: .leading)
    }
}
