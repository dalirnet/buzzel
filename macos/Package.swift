// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Buzzel",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Buzzel",
            targets: ["Buzzel"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Buzzel",
            path: "Sources"
        )
    ]
)
