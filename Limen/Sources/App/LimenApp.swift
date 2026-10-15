import LimenKit
import SwiftUI

@main
struct LimenApp: App {
    @State private var model: LimenModel = {
        #if DEBUG
        // A separate installed app and OS container are the boundary, even if reset arguments
        // accidentally reach the owner's production app. An environment flag is not a boundary.
        let isolated = Bundle.main.bundleIdentifier == "dev.peringer.limen.audit"
        let arguments = isolated ? ProcessInfo.processInfo.arguments : []
        if arguments.contains("LIMEN_RESET") || arguments.contains("LIMEN_DEMO") || arguments.contains("LIMEN_STORE") {
            LimenModel.resetForTests(prefs: .standard, root: AppFiles.support)
        }
        if isolated, let lang = ProcessInfo.processInfo.environment["LIMEN_LANG"] { UserDefaults.standard.set(lang, forKey: "lang") }
        if arguments.contains("LIMEN_DEMO") { LimenModel.seedDemo(into: Store(root: AppFiles.support), prefs: .standard) }
        // The store screenshots walk a scene of their own, one per language, and start at the
        // landing rather than inside the record, so this seeds without opening anything.
        if arguments.contains("LIMEN_STORE") {
            LimenModel.seedStoreScene(into: Store(root: AppFiles.support), prefs: .standard, lang: Lang.from(ProcessInfo.processInfo.environment["LIMEN_LANG"]))
        }
        #endif
        // Startup precedes any operation; only our private staging directories are swept.
        for directory in [AppFiles.scratch, AppFiles.captures] {
            for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
                try? FileManager.default.removeItem(at: file)
            }
        }
        return LimenModel()
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

/// The app under its theme: the case while no record is open, the flow while one is.
struct RootView: View {
    @Environment(LimenModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let colors: LimenColors = model.darkTheme ? .night : .day
        let s = model.str
        ZStack {
            (model.working == nil ? colors.landing : colors.plate).ignoresSafeArea()
            if model.working != nil {
                FlowScreen()
                    .transition(.opacity)
            } else {
                HomeScreen()
                    .transition(.opacity)
            }
        }
        .environment(\.limen, colors)
        .environment(\.str, s)
        .environment(\.locale, s.lang.locale)
        // The system controls follow the in-app switch rather than the system setting, otherwise
        // sheets and menus invert against the plate the moment it does.
        .preferredColorScheme(model.darkTheme ? .dark : .light)
        .tint(colors.action)
        .animation(.easeInOut(duration: 0.18), value: model.working == nil)
        // The draft reaches the disk whenever this window stops: the camera suspends this app
        // routinely mid-handover, and the debounced write must never be what a handover loses.
        //
        // On .background, which is ON_STOP, and not on .inactive: a pulled-down Control Centre, a
        // banner, the app switcher and an incoming call all pass through .inactive, and a flush
        // there commits the six-second undo the moment the person glances away. Every path off the
        // screen passes through .background before the process can be ended.
        .alert(s.signatureEditWarning, isPresented: Binding(get: { model.pendingEdit != nil }, set: { if !$0 { model.cancelMaterialEdit() } })) {
            Button(s.cancel, role: .cancel) { model.cancelMaterialEdit() }
            Button(s.done) { model.confirmMaterialEdit() }
        } message: { Text(model.pendingEditNames.joined(separator: ", ")) }
        .overlay(alignment: .bottom) {
            if let error = model.saveError {
                VStack {
                    Text(error).font(.body).accessibilityLabel(error)
                    Button(s.retry) { model.persistWorking() }
                }.padding().background(.regularMaterial)
            } else if let error = model.evidenceError {
                VStack {
                    Text(error).font(.body)
                    Button(s.done) { model.evidenceError = nil }
                }.padding().background(.regularMaterial)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.flush()
                model.libraryUnlocked = false
                if model.libraryProtectionEnabled && model.working == nil { model.homePage = .landing }
            }
        }
    }
}
