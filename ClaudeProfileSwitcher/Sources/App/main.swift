import SwiftUI
import AppKit

// MARK: - App Entry Point

@main
struct ClaudeProfileSwitcherApp: App {
    @StateObject private var manager = ProfileManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(manager)
                .onAppear {
                    manager.discoverProfiles()
                    centerWindow()
                }
                .onReceive(manager.$shouldClose) { shouldClose in
                    if shouldClose { NSApp.terminate(nil) }
                }
        }
        // Backported for macOS 11+ — use frame on the VStack instead
    }

    private func centerWindow() {
        if let window = NSApp.windows.first {
            window.center()
            window.title = "Claude Profile Switcher"
            window.isMovableByWindowBackground = true
        }
    }
}

// MARK: - Profile Discovery & Switching

class ProfileManager: ObservableObject {
    @Published var profiles: [(name: String, isActive: Bool)] = []
    @Published var hasLegacyProfile = false
    @Published var isSwitching = false
    @Published var statusMessage = ""
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var shouldClose = false

    private let supportDir: URL
    private let claudeDir: URL
    private let fm = FileManager.default

    init() {
        supportDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        claudeDir = supportDir.appendingPathComponent("Claude", isDirectory: true)
    }

    // MARK: - Discovery

    func discoverProfiles() {
        profiles = []
        hasLegacyProfile = false

        // Check current Claude path
        var activeProfileName: String?
        if fm.fileExists(atPath: claudeDir.path) {
            if let dest = try? fm.destinationOfSymbolicLink(atPath: claudeDir.path) {
                let destURL = URL(fileURLWithPath: dest)
                let comp = destURL.lastPathComponent
                if comp.hasPrefix("Claude-") {
                    activeProfileName = String(comp.dropFirst("Claude-".count))
                } else {
                    activeProfileName = comp
                }
            } else {
                // Claude is a real directory — legacy state
                hasLegacyProfile = true
            }
        }

        // Enumerate Claude-* directories
        guard let contents = try? fm.contentsOfDirectory(
            at: supportDir,
            includingPropertiesForKeys: nil,
            options: .skipsSubdirectoryDescendants
        ) else {
            statusMessage = "Cannot read ~/Library/Application Support/"
            return
        }

        for url in contents {
            let name = url.lastPathComponent
            guard name.hasPrefix("Claude-"), name != "Claude" else { continue }
            let displayName = String(name.dropFirst("Claude-".count))
            guard !displayName.isEmpty else { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let active = (displayName == activeProfileName)
            profiles.append((name: displayName, isActive: active))
        }

        profiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if profiles.isEmpty && !hasLegacyProfile {
            statusMessage = "No profiles found.\nCreate a Claude-<Name> folder inside ~/Library/Application Support/."
        } else {
            statusMessage = ""
        }
    }

    // MARK: - Active profile name

    var activeProfileName: String? {
        profiles.first(where: \.isActive)?.name
    }

    // MARK: - Create new empty profile

    func createNewProfile(name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        guard !cleanName.isEmpty else {
            errorMessage = "Profile name cannot be empty."
            showError = true
            return
        }
        guard cleanName.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted.union(.whitespaces).subtracting(CharacterSet(charactersIn: "-_"))) == nil else {
            errorMessage = "Use letters, numbers, hyphens, and underscores only."
            showError = true
            return
        }

        let newDir = supportDir.appendingPathComponent("Claude-\(cleanName)", isDirectory: true)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: newDir.path, isDirectory: &isDir) {
            errorMessage = "Profile \"\(cleanName)\" already exists."
            showError = true
            return
        }

        isSwitching = true
        statusMessage = "Creating profile \"\(cleanName)\"..."

        do {
            try fm.createDirectory(at: newDir, withIntermediateDirectories: true)
            statusMessage = "Created \"\(cleanName)\". Switch to it and sign in fresh."
            discoverProfiles()
        } catch {
            errorMessage = "Failed to create profile: \(error.localizedDescription)"
            showError = true
        }

        isSwitching = false
    }

    // MARK: - Duplicate existing profile

    func duplicateProfile(from sourceName: String, to newName: String) {
        let cleanNew = newName.trimmingCharacters(in: .whitespaces)
        guard !cleanNew.isEmpty else {
            errorMessage = "Profile name cannot be empty."
            showError = true
            return
        }
        guard cleanNew.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted.union(.whitespaces).subtracting(CharacterSet(charactersIn: "-_"))) == nil else {
            errorMessage = "Use letters, numbers, hyphens, and underscores only."
            showError = true
            return
        }

        let sourceDir = supportDir.appendingPathComponent("Claude-\(sourceName)", isDirectory: true)
        let destDir = supportDir.appendingPathComponent("Claude-\(cleanNew)", isDirectory: true)

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: destDir.path, isDirectory: &isDir) {
            errorMessage = "Profile \"\(cleanNew)\" already exists."
            showError = true
            return
        }

        isSwitching = true
        statusMessage = "Duplicating \"\(sourceName)\" to \"\(cleanNew)\"..."

        do {
            try fm.copyItem(at: sourceDir, to: destDir)
            statusMessage = "Duplicated \"\(sourceName)\" → \"\(cleanNew)\"."
            discoverProfiles()
        } catch {
            errorMessage = "Failed to duplicate: \(error.localizedDescription)"
            showError = true
        }

        isSwitching = false
    }

    // MARK: - Convert legacy directory to profile

    func convertLegacyToProfile(name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Profile name cannot be empty."
            showError = true
            return
        }
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        let newDir = supportDir.appendingPathComponent("Claude-\(cleanName)", isDirectory: true)

        isSwitching = true
        statusMessage = "Converting current state to \"\(cleanName)\"..."

        do {
            try fm.moveItem(at: claudeDir, to: newDir)
            try fm.createSymbolicLink(at: claudeDir, withDestinationURL: newDir)
            statusMessage = "Converted to profile \"\(cleanName)\"."
            discoverProfiles()
        } catch {
            errorMessage = "Conversion failed: \(error.localizedDescription)"
            showError = true
            // Rollback attempt
            if !fm.fileExists(atPath: claudeDir.path) {
                _ = try? fm.moveItem(at: newDir, to: claudeDir)
            }
        }
        isSwitching = false
    }

    // MARK: - Switching

    func switchToProfile(_ name: String) {
        isSwitching = true
        statusMessage = "Switching to \"\(name)\"..."

        // 1. Quit Claude Desktop
        let quitTask = Process()
        quitTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        quitTask.arguments = ["-f", "Claude"]
        do {
            try quitTask.run()
            quitTask.waitUntilExit()
        } catch {
            // pkill not available or failed — continue anyway
        }

        // Brief pause for cleanup
        Thread.sleep(forTimeInterval: 0.5)

        let profileDir = supportDir.appendingPathComponent("Claude-\(name)", isDirectory: true)

        // Verify profile exists
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: profileDir.path, isDirectory: &isDir), isDir.boolValue else {
            errorMessage = "Profile directory \"Claude-\(name)\" does not exist."
            showError = true
            isSwitching = false
            return
        }

        // 2. Remove current Claude symlink (or directory)
        do {
            if fm.fileExists(atPath: claudeDir.path) {
                try fm.removeItem(at: claudeDir)
            }
        } catch {
            errorMessage = "Could not remove existing Claude: \(error.localizedDescription)"
            showError = true
            isSwitching = false
            return
        }

        // 3. Create new symlink
        do {
            try fm.createSymbolicLink(at: claudeDir, withDestinationURL: profileDir)
        } catch {
            errorMessage = "Could not create symlink: \(error.localizedDescription)"
            showError = true
            isSwitching = false
            return
        }

        statusMessage = "✅ Switched to \"\(name)\".\n\nRelaunch Claude Desktop?"
        isSwitching = false
        discoverProfiles()
    }

    // MARK: - Reset to original (undo profiles)

    func resetToOriginal() {
        isSwitching = true
        statusMessage = "Resetting to single-folder state..."

        // 1. Quit Claude Desktop
        let quitTask = Process()
        quitTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        quitTask.arguments = ["-f", "Claude"]
        try? quitTask.run()
        quitTask.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.5)

        // 2. Read where the symlink points
        guard let dest = try? fm.destinationOfSymbolicLink(atPath: claudeDir.path) else {
            errorMessage = "Claude is not a symlink — nothing to reset."
            showError = true
            isSwitching = false
            return
        }
        let destURL = URL(fileURLWithPath: dest)

        // 3. Remove symlink, move directory back
        do {
            try fm.removeItem(at: claudeDir)
            try fm.moveItem(at: destURL, to: claudeDir)
        } catch {
            errorMessage = "Reset failed: \(error.localizedDescription)"
            showError = true
            isSwitching = false
            return
        }

        statusMessage = "Reset complete. Claude is a regular folder again."
        hasLegacyProfile = true
        discoverProfiles()
        isSwitching = false
    }

    // MARK: - Relaunch

    func relaunchClaude() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Claude"]
        do {
            try task.run()
        } catch {
            errorMessage = "Could not launch Claude: \(error.localizedDescription)"
            showError = true
            return
        }
        // Auto-close the switcher after relaunch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.shouldClose = true
        }
    }
}

// MARK: - Views

struct ContentView: View {
    @EnvironmentObject var manager: ProfileManager

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            if manager.hasLegacyProfile {
                legacyConversionView
            } else if manager.profiles.isEmpty {
                emptyStateView
            } else {
                profileListView
                if !manager.statusMessage.isEmpty && !manager.isSwitching {
                    statusFooterView
                }
            }
            Spacer(minLength: 0)
            Divider()
            footerView
        }
        .frame(minWidth: 400, minHeight: 480)
        .alert("Error", isPresented: $manager.showError) {
            Button("OK") { }
        } message: {
            Text(manager.errorMessage)
        }
        .alert("Reset to single folder?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                manager.resetToOriginal()
            }
        } message: {
            Text("This will remove the symlink and move the current profile back to a plain Claude folder. Your profile folders will be preserved but no longer managed by this app.")
        }
        .sheet(isPresented: $showNewProfileSheet) {
            NewProfileSheet(isPresented: $showNewProfileSheet)
        }
        .sheet(isPresented: $showDuplicateSheet) {
            DuplicateSheet(
                isPresented: $showDuplicateSheet,
                sourceName: manager.activeProfileName ?? ""
            )
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.2.arrow.trianglehead.swap")
                .font(.system(size: 28))
                .foregroundColor(.accentColor)
                .padding(.top, 20)

            Text("Claude Profile Switcher")
                .font(.title3)
                .fontWeight(.semibold)

            // Mode badge
            HStack(spacing: 4) {
                Circle()
                    .fill(manager.hasLegacyProfile ? Color.green : Color.teal)
                    .frame(width: 7, height: 7)
                Text(manager.hasLegacyProfile ? "Normal Mode" : "Multi Profile")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(manager.hasLegacyProfile ? Color.green : Color.teal)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill((manager.hasLegacyProfile ? Color.green : Color.teal).opacity(0.1))
            )

            if !manager.isSwitching {
                let activeCount = manager.profiles.filter(\.isActive).count
                if activeCount > 0 {
                    Text("Active: \(manager.profiles.first(where: \.isActive)!.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if manager.isSwitching {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(manager.statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 8)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Legacy conversion

    private var legacyConversionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.orange)

            Text("Current Claude folder is a regular directory,\nnot a symlink. Convert it into a profile?")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                TextField("What would you like to name your Profile?", text: $legacyName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)

                Button("Convert") {
                    manager.convertLegacyToProfile(name: legacyName)
                    legacyName = ""
                }
                .buttonStyle(.bordered)
                .disabled(legacyName.trimmingCharacters(in: .whitespaces).isEmpty || manager.isSwitching)
            }

            Button("Skip — I'll set it up manually") {
                manager.discoverProfiles()
            }
            .buttonStyle(.link)
            .controlSize(.small)
        }
        .padding()
    }

    @State private var legacyName = "Personal"

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text(manager.statusMessage)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Refresh") {
                manager.discoverProfiles()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
    }

    // MARK: - Profile list

    private var profileListView: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Button(action: {
                    newProfileName = ""
                    showNewProfileSheet = true
                }) {
                    Label("＋ New", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(manager.isSwitching)

                Button(action: {
                    duplicateProfileName = ""
                    showDuplicateSheet = true
                }) {
                    Label("⧉ Duplicate", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(manager.activeProfileName == nil || manager.isSwitching)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(manager.profiles, id: \.name) { profile in
                        ProfileRow(
                            name: profile.name,
                            isActive: profile.isActive,
                            isLoading: manager.isSwitching,
                            action: { manager.switchToProfile(profile.name) }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Status + relaunch

    @ViewBuilder
    private var statusFooterView: some View {
        VStack(spacing: 8) {
            Text(manager.statusMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if manager.statusMessage.contains("Relaunch") {
                HStack(spacing: 12) {
                    Button(action: {
                        manager.relaunchClaude()
                    }) {
                        Label("Relaunch Claude Desktop", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)

                    Button("Quit Switcher") {
                        manager.shouldClose = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button("Quit") {
                manager.shouldClose = true
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if !manager.hasLegacyProfile {
                Button(action: {
                    manager.discoverProfiles()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            Button(action: {
                showResetConfirmation = true
            }) {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .help("Undo profiles: move current back to a plain Claude folder")
            .disabled(!manager.profiles.isEmpty && manager.hasLegacyProfile || manager.isSwitching)

            Button(action: {
                showHelp = true
            }) {
                Label("Help", systemImage: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showHelp) {
                helpPopover
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @State private var showHelp = false
    @State private var showResetConfirmation = false
    @State private var showNewProfileSheet = false
    @State private var showDuplicateSheet = false
    @State private var newProfileName = ""
    @State private var duplicateProfileName = ""

    private var helpPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How Profiles Work")
                .font(.headline)

            Text("1. Create folders in ~/Library/Application Support/")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("   • Claude-Personal")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 16)
            Text("   • Claude-Work")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 16)

            Text("2. Each folder is a complete Claude Desktop config.")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("3. The app swaps a symlink to activate one at a time.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            Text("by Dzineer")
                .font(.caption2)
                .foregroundColor(.secondary)
                .opacity(0.5)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
        .frame(width: 280)
    }
}

// MARK: - Profile Row

struct ProfileRow: View {
    let name: String
    let isActive: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                    .frame(width: 32, height: 32)

                Image(systemName: isActive ? "person.fill.checkmark" : "person.fill")
                    .font(.system(size: 14))
                    .foregroundColor(isActive ? .green : .secondary)
            }

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                    .fontWeight(isActive ? .semibold : .regular)

                Text(isActive ? "Active" : "Inactive")
                    .font(.caption)
                    .foregroundStyle(isActive ? Color.green : Color.gray.opacity(0.4))
            }

            Spacer()

            // Action
            if isActive {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.green.opacity(0.1)))
            } else {
                Button("Switch") {
                    action()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoading)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.accentColor.opacity(0.04) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - New Profile Sheet

struct NewProfileSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var manager: ProfileManager
    @State private var name: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 36))
                .foregroundColor(.accentColor)
                .padding(.top, 24)

            Text("Create New Profile")
                .font(.title3)
                .fontWeight(.semibold)

            Text("An empty profile lets you sign in to a\ndifferent Claude Desktop account.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 0) {
                Text("Claude-")
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
                TextField("ProfileName", text: $name)
                    .textFieldStyle(.plain)
                    .font(.body.monospaced())
                    .padding(.vertical, 6)
                    .padding(.trailing, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .frame(width: 260)

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    manager.createNewProfile(name: name)
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Spacer()
        }
        .frame(width: 340, height: 300)
    }
}

// MARK: - Duplicate Profile Sheet

struct DuplicateSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var manager: ProfileManager
    let sourceName: String
    @State private var name: String = ""

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.on.doc.fill")
                .font(.system(size: 36))
                .foregroundColor(.accentColor)
                .padding(.top, 24)

            Text("Duplicate Profile")
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: 4) {
                Text("Source:")
                    .foregroundColor(.secondary)
                Text(sourceName)
                    .fontWeight(.medium)
            }
            .font(.subheadline)

            Text("Creates an exact copy — same account,\nseparate chat history and settings.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 0) {
                Text("Claude-")
                    .foregroundColor(.secondary)
                    .padding(.leading, 8)
                TextField("CopyName", text: $name)
                    .textFieldStyle(.plain)
                    .font(.body.monospaced())
                    .padding(.vertical, 6)
                    .padding(.trailing, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .frame(width: 260)

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button("Duplicate") {
                    manager.duplicateProfile(from: sourceName, to: name)
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Spacer()
        }
        .frame(width: 340, height: 340)
    }
}
