// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "swift-file-cache",
    platforms: [.macOS(.v27), .iOS(.v27), .tvOS(.v27), .watchOS(.v27), .visionOS(.v27)],
    products: [.library(name: "File Cache", targets: ["File Cache"])],
    dependencies: [
        .package(url: "https://github.com/swift-atoms/swift-byte.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-file-system.git", branch: "main"),
        .package(url: "https://github.com/swift-standards/swift-fips-180-4.git", branch: "main"),
        .package(url: "https://github.com/swift-ietf/swift-rfc-1950.git", branch: "main"),
        .package(url: "https://github.com/swift-iso/swift-iso-9945.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "File Cache",
            dependencies: [
                .product(name: "Byte", package: "swift-byte"),
                .product(name: "File System", package: "swift-file-system"),
                .product(name: "FIPS 180-4 Digest", package: "swift-fips-180-4"),
                .product(name: "RFC 1950", package: "swift-rfc-1950"),
                .product(
                    name: "ISO 9945 Kernel Time",
                    package: "swift-iso-9945",
                    condition: .when(platforms: [.macOS, .iOS, .tvOS, .watchOS, .visionOS, .linux])
                ),
            ]
        ),
        .testTarget(
            name: "File Cache Tests",
            dependencies: [
                .target(name: "File Cache"),
                .product(name: "Byte", package: "swift-byte"),
                .product(name: "FIPS 180-4", package: "swift-fips-180-4"),
                .product(name: "File System Test Support", package: "swift-file-system"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    target.swiftSettings =
        (target.swiftSettings ?? []) + [
            .strictMemorySafety(),
            .enableUpcomingFeature("ExistentialAny"),
            .enableUpcomingFeature("InternalImportsByDefault"),
            .enableUpcomingFeature("MemberImportVisibility"),
            .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            .enableUpcomingFeature("InferIsolatedConformances"),
            .enableExperimentalFeature("Lifetimes"),
            .treatAllWarnings(as: .error),
        ]
}
