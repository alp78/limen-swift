import LimenKit
import SwiftUI

@main
struct LimenApp: App {
    @State private var model: LimenModel = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("LIMEN_RESET") || arguments.contains("LIMEN_DEMO") {
            LimenModel.resetForTests(prefs: .standard, root: AppFiles.support)
        }
        if let lang = ProcessInfo.processInfo.environment["LIMEN_LANG"] { UserDefaults.standard.set(lang, forKey: "lang") }
        if arguments.contains("LIMEN_DEMO") { LimenModel.seedDemo(into: Store(root: AppFiles.support), prefs: .standard) }
        #endif
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
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model.flush() }
        }
    }
}
