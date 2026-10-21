import ProjectDescription

// Limen, ported from the Android original at ~/DEV/ANDROID/limen. The Android source is the
// specification; the decisions behind every setting here are recorded in CLAUDE.md.

let iOSFloor = "17.0"
let deployment: DeploymentTargets = .iOS(iOSFloor)

// Strict concurrency stays on `complete` for the same reason the template chose it: data races
// the Kotlin original could only hit at runtime become compile errors here.
let baseSettings: SettingsDictionary = [
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": .string(iOSFloor),
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    // Android tinted the caret, the selection handles and every system widget from the
    // navy action colour; on iOS that is the accent colour, so it carries the same values.
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    // The name follows Android (1.2.5, versionCode 10): the version that reads repacked backups
    // has the same number on both platforms, so "restores in Limen 1.2.5 or later" is true on
    // each. The build number is this project's own sequence, with no 1.2.1, 1.2.3 or 1.2.4: 4 and
    // 6 were uploaded, 5 was archived and never uploaded, so 7 is the next.
    "MARKETING_VERSION": "1.2.5",
    "CURRENT_PROJECT_VERSION": "7",
    // The owner's own Apple Account (aperinger@proton.me), which is the one that will hold the
    // paid membership: an Individual enrollment needs no company, and Apple publishes the
    // enrolled legal name rather than any trade name. Pinning the team keeps a build from being
    // signed by the other identity on this Mac, because a bundle identifier registered once by
    // a team is closed to every other, which is how the previous namespace was lost.
    "DEVELOPMENT_TEAM": "KDSZB7N44K",
]

let project = Project(
    name: "Limen",
    // No synthesized asset accessors: they would generate a `LimenColors` type over the palette
    // this app already defines by that name from the Android theme.
    options: .options(defaultKnownRegions: ["en", "fr", "de", "it", "rm"], developmentRegion: "en", disableSynthesizedResourceAccessors: true),
    settings: .settings(base: baseSettings),
    targets: [
        // libjxl, the one piece of third-party code in the build, behind a C shim of two calls:
        // the JPEG photographs in a backup are repacked losslessly as JPEG XL and rebuilt byte for
        // byte on restore, as the Android app does since 1.2.5. The library arrives pinned through
        // tools/fetch-deps.sh and is built into ThirdParty/LimenJxl.xcframework by
        // tools/build-libjxl.sh; both are gitignored, and `make gen` names the commands when the
        // tree is missing.
        .target(
            name: "LimenJxl",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "dev.peringer.limen.jxl",
            deploymentTargets: deployment,
            sources: ["LimenJxl/Sources/**/*.c"],
            headers: .headers(public: ["LimenJxl/Sources/include/*.h"]),
            dependencies: [.xcframework(path: "ThirdParty/LimenJxl.xcframework")],
            settings: .settings(base: baseSettings)
        ),

        // Everything below the screens, mirroring the Android data, sense and photo packages
        // plus the strings and the PDF: the record and its JSON, the store, the archive and its
        // cipher, the fingerprint, the dates, the phone and address checks, the five languages
        // and the exported document. Foundation, CryptoKit, CommonCrypto, Compression, ImageIO
        // and UIKit's PDF renderer, plus libjxl through LimenJxl for the backups.
        .target(
            name: "LimenKit",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.peringer.limen.kit",
            deploymentTargets: deployment,
            sources: ["LimenKit/Sources/**"],
            resources: ["LimenKit/Resources/**"],
            dependencies: [.target(name: "LimenJxl")],
            // libjxl is C++, and the static archive it comes in asks for the C++ runtime at the
            // one place the symbols are resolved, which is this framework's own link.
            settings: .settings(base: baseSettings.merging(["OTHER_LDFLAGS": "$(inherited) -lc++"]) { _, new in new })
        ),

        .target(
            name: "Limen",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.peringer.limen",
            deploymentTargets: deployment,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Limen",
                "CFBundleLocalizations": ["en", "fr", "de", "it", "rm"],
                "NSFaceIDUsageDescription": "Limen uses Face ID only when you enable protection for the saved-record library and settings.",
                // Tuist's default Info.plist carries 1.0 and 1, which is what the built bundle
                // showed while the two settings above said 1.1.2 and 4. The phone's Settings pane
                // and the crash reports read the bundle, so the bundle has to be told.
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
                // The splash cannot read the saved day/night preference, so it wears the day
                // plate: day is the default face of this instrument.
                "UILaunchScreen": ["UIColorName": "DayPlate"],
                // Rotation is handled rather than survived, as the Android manifest declares.
                "UISupportedInterfaceOrientations": [
                    "UIInterfaceOrientationPortrait",
                    "UIInterfaceOrientationLandscapeLeft",
                    "UIInterfaceOrientationLandscapeRight",
                    "UIInterfaceOrientationPortraitUpsideDown",
                ],
                // The finished PDF and the encrypted backup are written to Documents, which
                // Files shows as On My iPhone / Limen: the iOS shape of Download/Limen.
                "UIFileSharingEnabled": true,
                "LSSupportsOpeningDocumentsInPlace": true,
                // Android took defect photographs through the system camera app with no
                // permission of its own; iOS has no such route, so the camera is asked for
                // once. Nothing the camera writes leaves the app's private storage.
                "NSCameraUsageDescription": "Limen photographs defects and supplied items for the handover record. Photos stay in this app's private storage and leave the phone only in the PDF or backup you export.",
                // Deliberately absent. The app implements its own AES-256-GCM for the encrypted
                // backup rather than only calling the operating system's TLS, so the blanket "false"
                // this key used to carry was very likely the wrong declaration. Without the key App
                // Store Connect asks the export compliance question on every upload, with Apple's
                // own criteria on the page, and the answer is given there rather than asserted here.
            ]),
            sources: ["Limen/Sources/**"],
            // The third-party notice ships INSIDE the app, referenced at the repository root
            // rather than copied under Resources: Apache-2.0 section 4(d) asks for it to travel
            // with the distribution, and two hand-maintained copies of a licence notice drift
            // apart.
            resources: ["Limen/Resources/**", "NOTICE"],
            dependencies: [.target(name: "LimenKit")],
            settings: .settings(base: baseSettings, configurations: [
                .debug(name: "Debug", settings: ["PRODUCT_BUNDLE_IDENTIFIER": "dev.peringer.limen.audit"]),
                .release(name: "Release", settings: ["PRODUCT_BUNDLE_IDENTIFIER": "dev.peringer.limen"]),
            ])
        ),

        .target(
            name: "LimenKitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.peringer.limen.kit.tests",
            deploymentTargets: deployment,
            sources: ["LimenKitTests/Sources/**"],
            resources: [.folderReference(path: "LimenKitTests/Fixtures/Compatibility")],
            // Hosted in the app, as LimenTests is: a tool-hosted test bundle cannot run on a
            // phone, and the libjxl round trip and the larger-than-memory backup have to.
            dependencies: [.target(name: "LimenKit"), .target(name: "Limen")],
            settings: .settings(base: baseSettings)
        ),

        .target(
            name: "LimenTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.peringer.limen.tests",
            deploymentTargets: deployment,
            sources: ["LimenTests/Sources/**"],
            dependencies: [.target(name: "Limen")],
            settings: .settings(base: baseSettings)
        ),

        .target(
            name: "LimenUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "dev.peringer.limen.uitests",
            deploymentTargets: deployment,
            sources: ["LimenUITests/Sources/**"],
            // LimenKit rides along so the five-language walk can assert on `Str` itself rather
            // than on a table of expected words retyped here, which would drift from the
            // generated strings the moment a translation changed.
            dependencies: [.target(name: "Limen"), .target(name: "LimenKit")],
            settings: .settings(base: baseSettings)
        ),
    ],
    schemes: [
        .scheme(
            name: "AllTests",
            shared: true,
            buildAction: .buildAction(targets: ["LimenKit", "Limen"]),
            testAction: .targets(
                [
                    .testableTarget(target: "LimenKitTests"),
                    .testableTarget(target: "LimenTests"),
                    .testableTarget(target: "LimenUITests"),
                ],
                options: .options(coverage: true)
            )
        )
    ]
)
