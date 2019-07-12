// swift-tools-version:5.0
import PackageDescription
let package = Package(
    name: "MongoSwift",
    products: [
        .library(name: "MongoSwift", targets: ["MongoSwift"])
    ],
    dependencies: [
        .package(url: "https://github.com/Quick/Nimble.git", .upToNextMajor(from: "8.0.0"))
    ],
    targets: [
        .target(name: "MongoSwift", dependencies: ["CLibMongoC"]),
        .target(name: "AtlasConnectivity", dependencies: ["MongoSwift"]),
        .testTarget(name: "MongoSwiftTests", dependencies: ["MongoSwift", "Nimble"]),
        .target(
            name: "CLibMongoC",
            dependencies: [],
            cSettings: [
                .define("MONGO_SWIFT_OS_LINUX", .when(platforms: [.linux])),
                .define("MONGO_SWIFT_OS_DARWIN", .when(platforms: [.iOS, .macOS])),
                .define("BSON_COMPILATION"),
                .define("MONGOC_COMPILATION"),
                .headerSearchPath("common")
            ],
            linkerSettings: [
                .linkedLibrary("resolv"),
                .linkedLibrary("ssl", .when(platforms: [.linux])),
                .linkedLibrary("crypto", .when(platforms: [.linux])),
                .linkedLibrary("z", .when(platforms: [.linux]))
            ]
        )
    ]
)
