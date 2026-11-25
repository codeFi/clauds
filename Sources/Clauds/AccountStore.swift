import AppKit
import Foundation

struct Account: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    /// Optional. Only shown in the panel.
    var email: String? = nil
}

private struct SavedState: Codable {
    var accounts: [Account] = []
    var activeID: UUID?
    var sideBySide: Bool?
    var shareSessions: Bool?
    var autoSwitch: AutoSwitch.Mode?
    var shareInSideBySide: Bool?
}

enum SwitchError: LocalizedError {
    case claudeWouldNotQuit
    case profileFolderInTheWay(String)
    case message(String)

    var errorDescription: String? {
        switch self {
        case .claudeWouldNotQuit:
            return "Claude did not quit in 60 seconds. Close Claude yourself, then try again."
        case .profileFolderInTheWay(let path):
            return "A folder is already at \(path). Nothing was changed."
        case .message(let text):
            return text
        }
    }
}

/// Keeps one Claude desktop data folder per account.
///
/// The active account's data lives where Claude expects it:
///   ~/Library/Application Support/Claude
/// Every other account's data waits in:
///   ~/Library/Application Support/Clauds/Profiles/<account id>
///
/// A switch quits Claude, renames the folders (instant, same disk), and opens Claude again.
/// Renaming keeps every account signed in.
@MainActor
final class AccountStore: ObservableObject {
    static let claudeBundleID = "com.anthropic.claudefordesktop"

    @Published private(set) var accounts: [Account] = []
    @Published private(set) var activeID: UUID?
    @Published private(set) var isSwitching = false
    /// Side-by-side mode: one Claude copy per account, all open at the same time. No restart on switch.
    @Published private(set) var sideBySide = false
    /// The user's setting: all accounts use the same Code session files.
    @Published private(set) var shareSessions = true
    /// The user's risky setting: share session files also in Side by Side. Off by default.
    /// Two open Claude copies that write the same files can make a session lose messages, split,
    /// or go back to an old state. The panel shows this warning before it turns the setting on.
    @Published private(set) var shareInSideBySide = false
    /// Side by Side shares session files only when the user turned that on.
    var sessionsAreShared: Bool { shareSessions && (!sideBySide || shareInSideBySide) }
    /// Accounts that have a Claude copy open now.
    @Published private(set) var runningIDs: Set<UUID> = []
    /// Plan usage per account, read from the files that the Claude app saves on this Mac.
    @Published private(set) var usage: [UUID: Usage] = [:]
    /// Result of the last live usage read per account (ok, sign-in needed, or failed).
    @Published private(set) var liveState: [UUID: LiveUsage.State] = [:]
    /// Accounts with a live usage read in progress now. The panel shows an activity indicator for them.
    @Published private(set) var loadingIDs: Set<UUID> = []
    /// Auto-switch near a limit: off, ask first, or automatic. Off until the user turns it on.
    @Published private(set) var autoSwitch: AutoSwitch.Mode = .off
    /// Shown in the panel after an automatic switch, until the panel closes.
    @Published private(set) var autoSwitchNote: (title: String, detail: String)?
    private var autoSwitchPausedUntil = Date.distantPast
    private var liveUsage: [UUID: Usage] = [:]
    private var lastLiveFetch = Date.distantPast
    private var liveTimer: Timer?

    let fm = FileManager.default
    let supportDir: URL
    let profilesDir: URL
    let stateFile: URL
    let claudeDir: URL
    let sharedSessionsDir: URL

    /// True: fake accounts for the screenshots. Reads and writes no files. Starts no Claude copy.
    let isDemo: Bool

    init(demo: Bool = false) {
        isDemo = demo
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        claudeDir = appSupport.appendingPathComponent("Claude", isDirectory: true)
        // Data of the old app name moves to the new folder, only while Claude is closed (see Migration).
        supportDir = demo
            ? appSupport.appendingPathComponent(Migration.folderName, isDirectory: true)
            : Migration.supportFolder(
                in: appSupport, claudeDir: claudeDir,
                claudeIsOpen: !NSRunningApplication.runningApplications(withBundleIdentifier: Self.claudeBundleID).isEmpty)
        profilesDir = supportDir.appendingPathComponent("Profiles", isDirectory: true)
        stateFile = supportDir.appendingPathComponent("accounts.json")
        sharedSessionsDir = supportDir.appendingPathComponent("SharedSessions", isDirectory: true)
        if demo { return }
        try? fm.createDirectory(at: profilesDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: sharedSessionsDir, withIntermediateDirectories: true)
        // Only your macOS user can open these folders.
        for dir in [supportDir, profilesDir, sharedSessionsDir] {
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
        load()

        // Keep the "open now" marks current.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshRunning()
                    // A Claude copy quit or started. Wait for its helpers, then fix idle folders.
                    try? await Task.sleep(for: .seconds(4))
                    self?.tidyIdleFolders()
                }
            }
        }
        refreshRunning()
        tidyIdleFolders()

        // Usage numbers every 2 minutes, also while the panel is closed.
        liveTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshUsage() }
        }
        refreshUsage()
    }

    var activeAccount: Account? { accounts.first { $0.id == activeID } }

    /// Owner mark for sessions that an account makes while sessions are shared.
    nonisolated static func tag(_ id: UUID) -> String { "switcher:\(id.uuidString)" }

    func profileDir(for id: UUID) -> URL {
        profilesDir.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: stateFile),
              let state = try? JSONDecoder().decode(SavedState.self, from: data) else { return }
        accounts = state.accounts
        activeID = state.activeID
        sideBySide = state.sideBySide ?? false
        shareSessions = state.shareSessions ?? true
        autoSwitch = state.autoSwitch ?? .off
        shareInSideBySide = state.shareInSideBySide ?? false
    }

    private func save() {
        guard !isDemo else { return }
        let state = SavedState(accounts: accounts, activeID: activeID, sideBySide: sideBySide,
                               shareSessions: shareSessions, autoSwitch: autoSwitch,
                               shareInSideBySide: shareInSideBySide)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(state) {
            try? data.write(to: stateFile, options: .atomic)
        }
    }

    // MARK: Account list

    /// First run: the login that Claude has now becomes an account. No files move.
    func adoptCurrentLogin(name: String) {
        let account = Account(id: UUID(), name: name)
        accounts.append(account)
        activeID = account.id
        save()
    }

    /// A new, empty account. Claude shows its sign-in screen the first time you switch to it.
    @discardableResult
    func addAccount(name: String) -> Account {
        let account = Account(id: UUID(), name: name)
        accounts.append(account)
        if activeID == nil { activeID = account.id }
        save()
        return account
    }

    func rename(_ account: Account, to name: String) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index].name = name
        save()
    }

    func setEmail(_ account: Account, to email: String?) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index].email = email
        save()
    }

    /// Puts the newest usage numbers in `usage`: the local file of the Claude app, or the live
    /// numbers from claude.ai when those are newer. Also starts a live read (not more than one in 45 s).
    func refreshUsage() {
        guard !isDemo else { return }
        var result: [UUID: Usage] = [:]
        for account in accounts {
            let dir = account.id == activeID ? claudeDir : profileDir(for: account.id)
            let local = Usage.read(dataDir: dir)
            // Live numbers have the reset times. Keep them while they are not older than 10 minutes.
            if let live = liveUsage[account.id],
               live.sampledAt >= (local?.sampledAt ?? .distantPast) || Date().timeIntervalSince(live.sampledAt) < 600 {
                result[account.id] = live
            } else {
                result[account.id] = local
            }
        }
        if result != usage { usage = result }
        refreshLiveUsage()
    }

    /// Screenshots only: puts fake accounts in the panel.
    func applyDemo(accounts: [Account], activeID: UUID, sideBySide: Bool, running: Set<UUID>, usage: [UUID: Usage],
                   loading: Set<UUID> = [], states: [UUID: LiveUsage.State] = [:]) {
        guard isDemo else { return }
        self.accounts = accounts
        self.activeID = activeID
        self.sideBySide = sideBySide
        self.runningIDs = running
        self.usage = usage
        self.loadingIDs = loading
        self.liveState = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, states[$0.id] ?? .ok) })
    }

    /// Build check only (preview picture).
    func usePreviewUsage(_ preview: [UUID: Usage]) {
        for (id, value) in preview { liveUsage[id] = value; usage[id] = value }
    }

    /// Asks claude.ai for the live usage of each account (through the account's own signed-in web view).
    func refreshLiveUsage(force: Bool = false) {
        guard !isDemo else { return }
        guard force || Date().timeIntervalSince(lastLiveFetch) > 45 else { return }
        lastLiveFetch = Date()
        LiveUsage.shared.debugFile = supportDir.appendingPathComponent("usage-debug.json")
        let list = accounts
        Task {
            loadingIDs.formUnion(list.map(\.id))
            for account in list {
                let (live, state) = await LiveUsage.shared.fetch(for: account)
                loadingIDs.remove(account.id)
                liveState[account.id] = state
                if let live { liveUsage[account.id] = live }
            }
            lastLiveFetch = Date()
            // Merge without a new live read.
            var result = usage
            for (id, live) in liveUsage where live.sampledAt >= (result[id]?.sampledAt ?? .distantPast) {
                result[id] = live
            }
            if result != usage { usage = result }
            checkAutoSwitch()
        }
    }

    // MARK: Auto-switch

    func setAutoSwitch(_ mode: AutoSwitch.Mode) {
        autoSwitch = mode
        autoSwitchPausedUntil = .distantPast
        save()
    }

    func clearAutoSwitchNote() { autoSwitchNote = nil }

    /// Runs after each live usage read. When the current account is near a limit and a different
    /// account has room, this asks (mode "ask") or switches (mode "auto").
    /// Does nothing in Side by Side, during a switch, or while Claude is closed.
    func checkAutoSwitch() {
        guard !isDemo, autoSwitch != .off, !sideBySide, !isSwitching, isClaudeRunning,
              Date() >= autoSwitchPausedUntil,
              let current = activeAccount,
              let plan = AutoSwitch.proposal(accounts: accounts, activeID: activeID, usage: usage)
        else { return }
        autoSwitchPausedUntil = Date().addingTimeInterval(AutoSwitch.pause)

        let reason = "\(plan.limit.fullName): \(plan.limit.currentPercent)% used."
        if autoSwitch == .ask {
            guard Prompt.confirm(
                title: "\(current.name) is near a limit",
                message: "\(reason) \(plan.target.name) has more room (\(plan.targetPercent)% used).\n\nSwitch to \(plan.target.name)? Claude quits and opens again with that account. Running Claude Code sessions in the app stop.",
                button: "Switch")
            else { return }
        }
        Task {
            do {
                try await switchTo(plan.target)
                autoSwitchNote = ("Switched to \(plan.target.name)", "\(current.name) was near a limit. \(reason)")
            } catch {
                Prompt.error(error)
            }
        }
    }

    func move(_ account: Account, by offset: Int) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        let target = index + offset
        guard accounts.indices.contains(target) else { return }
        accounts.swapAt(index, target)
        save()
    }

    /// Removes an account that is not active. Its saved Claude data goes to the Trash.
    func remove(_ account: Account) throws {
        guard account.id != activeID else {
            throw SwitchError.message("You cannot remove the active account. Switch to a different account first.")
        }
        guard runningApp(for: account) == nil else {
            throw SwitchError.message("This account has a Claude window open. Quit that Claude first.")
        }
        let dir = profileDir(for: account.id)
        if fm.fileExists(atPath: dir.path) {
            // Safety: first move this account's Code sessions to the shared pool, so they are not lost.
            try SessionLinker.link(claudeDir: dir, sharedDir: sharedSessionsDir, accountTag: Self.tag(account.id))
            try fm.trashItem(at: dir, resultingItemURL: nil)
        }
        accounts.removeAll { $0.id == account.id }
        save()
    }

    // MARK: Switching

    func switchTo(_ target: Account) async throws {
        guard target.id != activeID, !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }

        try await quitClaude()

        let current = activeID
        let claudeDir = self.claudeDir
        let targetDir = profileDir(for: target.id)
        let parkDir = current.map { profileDir(for: $0) }
        let sharedDir = sharedSessionsDir
        let share = sessionsAreShared
        let currentTag = current.map { Self.tag($0) }
        let targetTag = Self.tag(target.id)

        try await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default

            // 0. Record the owner of new shared sessions: the outgoing account made them.
            //    Then put its Code sessions in the wanted state (shared or separate).
            if share, let currentTag { try SessionLinker.claimUnknown(sharedDir: sharedDir, tag: currentTag) }
            try SessionLinker.apply(claudeDir: claudeDir, sharedDir: sharedDir, share: share, accountTag: currentTag)

            // 1. Park the active account's data.
            var parked = false
            if fm.fileExists(atPath: claudeDir.path) {
                guard let parkDir else {
                    throw SwitchError.message("Claude data has no account. Use \"Save current login as account\" first.")
                }
                if fm.fileExists(atPath: parkDir.path) {
                    throw SwitchError.profileFolderInTheWay(parkDir.path)
                }
                try fm.moveItem(at: claudeDir, to: parkDir)
                parked = true
            }

            // 2. Bring the target account's data in. A new account has no data: Claude starts at sign-in.
            if fm.fileExists(atPath: targetDir.path) {
                do {
                    try fm.moveItem(at: targetDir, to: claudeDir)
                } catch {
                    // Undo step 1 so Claude still opens with the old account.
                    if parked, let parkDir { try? fm.moveItem(at: parkDir, to: claudeDir) }
                    throw error
                }
                // 3. The same for the incoming account.
                try SessionLinker.apply(claudeDir: claudeDir, sharedDir: sharedDir, share: share, accountTag: targetTag)
            }
        }.value

        activeID = target.id
        save()
        openClaude()
    }

    /// Quits all Claude copies, puts every account's session folder in the wanted state
    /// (shared or separate), and opens the main Claude again if it was open.
    /// `change` runs after Claude quit, so a failed quit changes nothing.
    func applySessionLayout(change: () -> Void = {}) async throws {
        guard !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }
        let wasRunning = isClaudeRunning
        try await quitClaude()
        let wasShared = sessionsAreShared
        let activeTag = activeID.map { Self.tag($0) }
        change()
        save()
        // No Claude copy runs now, so it is safe to change every folder.
        let dirs: [(URL, String?)] = [(claudeDir, activeTag)] + accounts.map { (profileDir(for: $0.id), Self.tag($0.id)) }
        let sharedDir = sharedSessionsDir
        let share = sessionsAreShared
        try await Task.detached {
            // Sessions made while shared belong to the account that ran then (the main account).
            if wasShared, let activeTag { try SessionLinker.claimUnknown(sharedDir: sharedDir, tag: activeTag) }
            for (dir, tag) in dirs {
                try SessionLinker.apply(claudeDir: dir, sharedDir: sharedDir, share: share, accountTag: tag)
            }
        }.value
        if wasRunning { openClaude() }
        refreshRunning()
    }

    /// Automatic safety step. Puts the session folder of every account that has NO open Claude copy
    /// in the wanted state (shared or separate). Folders of open copies are not touched.
    func tidyIdleFolders() {
        guard !isSwitching else { return }
        let idleDirs: [(URL, String)] = accounts
            .filter { runningApp(for: $0) == nil }
            .map { ($0.id == activeID ? claudeDir : profileDir(for: $0.id), Self.tag($0.id)) }
        let sharedDir = sharedSessionsDir
        let share = sessionsAreShared
        Task.detached {
            for (dir, tag) in idleDirs {
                try? SessionLinker.apply(claudeDir: dir, sharedDir: sharedDir, share: share, accountTag: tag)
            }
        }
    }

    /// Use this one time after the first sign-in of a new account.
    func syncSessionsNow() async throws {
        try await applySessionLayout()
    }

    /// The "Share Code Sessions" switch. In Side by Side it changes the risky setting `shareInSideBySide`.
    func setShareSessions(_ on: Bool) async throws {
        try await applySessionLayout {
            if self.sideBySide {
                self.shareInSideBySide = on
                if on { self.shareSessions = true }
            } else {
                self.shareSessions = on
            }
        }
    }

    // MARK: Side-by-side mode

    /// The data folder of an account in side-by-side mode.
    /// The main account (activeID) uses Claude's normal folder. Each other account uses its saved folder.
    private func sideBySideDir(for account: Account) -> URL {
        account.id == activeID ? claudeDir : profileDir(for: account.id)
    }

    /// The Claude copy that runs for this account, if one is open.
    func runningApp(for account: Account) -> NSRunningApplication? {
        let isMain = account.id == activeID
        let marker = "--user-data-dir=" + profileDir(for: account.id).path
        return NSRunningApplication.runningApplications(withBundleIdentifier: Self.claudeBundleID).first { app in
            let command = Self.commandLine(of: app.processIdentifier)
            return isMain ? !command.contains("--user-data-dir=") : command.contains(marker)
        }
    }

    func refreshRunning() {
        guard !isDemo else { return }
        runningIDs = Set(accounts.filter { runningApp(for: $0) != nil }.map(\.id))
    }

    /// Brings the account's Claude copy to the front. Starts a copy if none is open. Nothing else quits.
    func showSideBySide(_ account: Account) async throws {
        if let app = runningApp(for: account) {
            app.activate()
            return
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.claudeBundleID) else {
            throw SwitchError.message("The Claude app was not found.")
        }
        let dir = sideBySideDir(for: account)
        let isMain = account.id == activeID
        let sharedDir = sharedSessionsDir
        let tag = Self.tag(account.id)
        let share = sessionsAreShared
        try await Task.detached {
            let fm = FileManager.default
            if !isMain {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            }
            // Separate files, unless the user turned on sharing in Side by Side.
            // This account's copy is not open, so the change of its folder is safe.
            try SessionLinker.apply(claudeDir: dir, sharedDir: sharedDir, share: share, accountTag: tag)
        }.value

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = true
        if !isMain { config.arguments = ["--user-data-dir=\(dir.path)"] }
        _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        refreshRunning()
    }

    /// Claude copies of accounts other than the main account.
    var extraCopies: [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: Self.claudeBundleID).filter {
            Self.commandLine(of: $0.processIdentifier).contains("--user-data-dir=")
        }
    }

    /// Turns side-by-side mode on or off. All Claude copies quit, because the session folders change.
    /// On: every account gets its own separate session files, unless `shareInSideBySide` is on.
    /// Off: session sharing is turned on again, and the separate files merge back (newer file wins).
    func setSideBySide(_ on: Bool) async throws {
        try await applySessionLayout {
            self.sideBySide = on
            if !on { self.shareSessions = true }
        }
    }

    nonisolated static func commandLine(of pid: pid_t) -> String {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-ww", "-o", "command=", "-p", String(pid)]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Claude app control

    var isClaudeRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.claudeBundleID).isEmpty
    }

    func openClaude() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.claudeBundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    /// Quits every Claude copy and waits until its process is gone.
    ///
    /// The check uses the process id, not `NSRunningApplication.isTerminated`: a Claude copy with
    /// open sessions can take much longer than a second to end, and the data folders must not move
    /// while its process is alive.
    private func quitClaude() async throws {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.claudeBundleID)
        guard !running.isEmpty else { return }
        let pids = running.map(\.processIdentifier)
        running.forEach { $0.terminate() }

        let start = Date()
        var flagSeconds: Double?
        var processSeconds: Double?
        // Wait up to 60 seconds for a clean quit.
        for _ in 0..<240 {
            let now = Date().timeIntervalSince(start)
            if flagSeconds == nil, running.allSatisfy(\.isTerminated) { flagSeconds = now }
            if pids.allSatisfy({ !Self.processIsAlive($0) }) { processSeconds = now; break }
            try await Task.sleep(for: .milliseconds(250))
        }
        recordQuit(copies: pids.count, flagSeconds: flagSeconds, processSeconds: processSeconds)
        guard processSeconds != nil else { throw SwitchError.claudeWouldNotQuit }

        // Wait up to 10 more seconds for helper processes (renderers, VM) to exit and release files.
        for _ in 0..<40 {
            if !Self.claudeHelpersRunning() { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        try await Task.sleep(for: .seconds(1))
    }

    /// True while the process exists. `kill` with signal 0 sends nothing: it only asks.
    nonisolated static func processIsAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Writes how long the last quit took to `quit-debug.json`. It holds numbers only.
    private func recordQuit(copies: Int, flagSeconds: Double?, processSeconds: Double?) {
        var record: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date()), "copies": copies]
        if let flagSeconds { record["secondsUntilAppKitSaidQuit"] = (flagSeconds * 100).rounded() / 100 }
        if let processSeconds { record["secondsUntilProcessGone"] = (processSeconds * 100).rounded() / 100 }
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]) else { return }
        let file = supportDir.appendingPathComponent("quit-debug.json")
        try? data.write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    /// True while any process runs from inside Claude.app.
    nonisolated static func claudeHelpersRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-f", "Claude.app/Contents/"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}
