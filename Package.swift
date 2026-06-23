// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MuteMeBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MuteMeBar",
            path: "Sources/MuteMeBar",
            exclude: ["Info.plist"],
            linkerSettings: [
                // Embed Info.plist so LSUIElement (no Dock icon) takes effect
                // when running the raw binary. The make-app.sh script also
                // places the plist inside the .app bundle.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/MuteMeBar/Info.plist",
                ])
            ]
        )
    ]
)
