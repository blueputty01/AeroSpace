import Common
import Foundation
import SwiftUI

@MainActor
public func menuBar(viewModel: TrayMenuModel) -> some Scene { // todo should it be converted to "SwiftUI struct"?
    MenuBarExtra {
        let shortIdentification = "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitShortHash)"
        let identification      = "\(aeroSpaceAppName) v\(aeroSpaceAppVersion) \(gitHash)"
        Text(shortIdentification)
        Button("Copy to clipboard") { identification.copyToClipboard() }
            .keyboardShortcut("C", modifiers: .command)
        Divider()
        if let token: RunSessionGuard = .isServerEnabled {
            Text("Workspaces:")
            ForEach(viewModel.workspaces, id: \.name) { workspace in
                Button {
                    Task {
                        try await runSession(.menuBarButton, token) { _ = Workspace.get(byName: workspace.name).focusWorkspace() }
                    }
                } label: {
                    Toggle(isOn: .constant(workspace.isFocused)) {
                        Text(workspace.name + workspace.suffix).font(.system(.body, design: .monospaced))
                    }
                }
            }
            Divider()
        }
        Button(viewModel.isEnabled ? "Disable" : "Enable") {
            Task {
                try await runSession(.menuBarButton, .forceRun) { () throws in
                    _ = try await EnableCommand(args: EnableCmdArgs(rawArgs: [], targetState: .toggle))
                        .run(.defaultEnv, .emptyStdin)
                }
            }
        }.keyboardShortcut("E", modifiers: .command)
        let editor = getTextEditorToOpenConfig()
        Button("Open config in '\(editor.lastPathComponent)'") {
            let fallbackConfig: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName)
            switch findCustomConfigUrl() {
            case .file(let url):
                url.open(with: editor)
            case .noCustomConfigExists:
                _ = try? FileManager.default.copyItem(atPath: defaultConfigUrl.path, toPath: fallbackConfig.path)
                fallbackConfig.open(with: editor)
            case .ambiguousConfigError:
                fallbackConfig.open(with: editor)
            }
        }.keyboardShortcut(",", modifiers: .command)
        if let token: RunSessionGuard = .isServerEnabled {
            Button("Reload config") {
                Task {
                    try await runSession(.menuBarButton, token) { _ = reloadConfig() }
                }
            }.keyboardShortcut("R", modifiers: .command)
        }
        Button("Quit \(aeroSpaceAppName)") {
            Task {
                defer { terminateApp() }
                try await terminationHandler.beforeTermination()
            }
        }.keyboardShortcut("Q", modifiers: .command)
    } label: {
        if viewModel.isEnabled {
            MenuLabel(viewModel: viewModel)
                .id(
                    "\(viewModel.workspaces.hashValue)\(viewModel.trayItems.hashValue)\(viewModel.isFullscreen.hashValue)"
                )
        } else {
            Image(systemName: "pause.rectangle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

struct MenuLabel: View {
    var viewModel: TrayMenuModel

    var body: some View {
        if #available(macOS 14, *) { // https://github.com/nikitabobko/AeroSpace/issues/1122
            let renderer = ImageRenderer(content: imageContent)
            if let cgImage = renderer.cgImage {
                Image(cgImage, scale: 2, label: Text(viewModel.trayText))
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // In case image can't be rendered fallback to default text
                Text(viewModel.trayText)
            }
        } else {
            // In case image can't be rendered fallback to default text
            Text(viewModel.trayText)
        }
    }

    // I used a height that's twice as large as what I want and then use a scale of 2 to make the images look smoother
    private var imageContent: some View {
        HStack(spacing: 4) {
            switch config.menuBarStyle {
            case .text:
                Text(viewModel.trayText).monospaced().font(.system(size:28))
            case .image, .full:
                if (viewModel.isFullscreen) {
                    Text("F").font(.system(size:28))
                }
                ForEach(viewModel.trayItems, id:\.name) { item in
                    Image(systemName: item.systemImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .id(item.name)
                }
                if config.menuBarStyle == .full {
                    let otherWorkspaces = Workspace.all.filter { workspace in
                        !workspace.isEffectivelyEmpty && !viewModel.trayItems.contains(where: { item in item.name == workspace.name })
                    }
                    if !otherWorkspaces.isEmpty {
                        Text("|").monospaced()
                        ForEach(otherWorkspaces, id:\.name) { item in
                            Text(item.name).monospaced().font(.system(size:28))
                        }
                    }
                }
            }
        }
        .frame(height: 40)
    }
}

enum MenuBarStyle: String {
    case text = "text"
    case image = "image"
    case full = "image-with-background-workspaces"
}

extension String {
    func parseMenuBarStyle() -> MenuBarStyle? {
        if let parsed = MenuBarStyle(rawValue: self) {
            return parsed
        } else {
            return nil
        }
    }
}

func getTextEditorToOpenConfig() -> URL {
    NSWorkspace.shared.urlForApplication(toOpen: findCustomConfigUrl().urlOrNil ?? defaultConfigUrl)?
        .takeIf { $0.lastPathComponent != "Xcode.app" } // Blacklist Xcode. It is too heavy to open plain text files
    ?? URL(filePath: "/System/Applications/TextEdit.app")
}
