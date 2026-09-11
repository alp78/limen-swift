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
    // The same pair as the Android build, whose code 3 was spent on the first closed test that
    // cited the Vaud RULV in every canton. (An earlier comment here said 1.1.1 was pinned by the
    // published privacy page naming the version its claims were checked against; none of the
    // five notices names a version, so nothing holds the name back.)
    "MARKETING_VERSION": "1.1.2",
    "CURRENT_PROJECT_VERSION": "4",
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
        // Everything below the screens, mirroring the Android data, sense and photo packages
        // plus the strings and the PDF: the record and its JSON, the store, the archive and its
        // cipher, the fingerprint, the dates, the phone and address checks, the five languages
        // and the exported document. Foundation, CryptoKit, CommonCrypto, Compression, ImageIO
        // and UIKit's PDF renderer only; no third-party code.
        .target(
            name: "LimenKit",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.peringer.limen.kit",
            deploymentTargets: deployment,
            sources: ["LimenKit/Sources/**"],
            resources: ["LimenKit/Resources/**"],
            settings: .settings(base: baseSettings)
        ),

        .target(
            name: "Limen",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.peringer.limen",
            deploymentTargets: deployment,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Limen",
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
                "ITSAppUsesNonExemptEncryption": false,
            ]),
            sources: ["Limen/Sources/**"],
            // The third-party notice ships INSIDE the app, referenced at the repository root
            // rather than copied under Resources: Apache-2.0 section 4(d) asks for it to travel
            // with the distribution, and two hand-maintained copies of a licence notice drift
            // apart.
            resources: ["Limen/Resources/**", "NOTICE"],
            dependencies: [.target(name: "LimenKit")],
            settings: .settings(base: baseSettings)
        ),

        .target(
            name: "LimenKitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.peringer.limen.kit.tests",
            deploymentTargets: deployment,
            sources: ["LimenKitTests/Sources/**"],
            dependencies: [.target(name: "LimenKit")],
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
            dependencies: [.target(name: "Limen")],
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
