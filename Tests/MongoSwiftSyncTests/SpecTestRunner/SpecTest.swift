import Foundation
@testable import MongoSwift
import Nimble
import TestsCommon
import XCTest

/// A struct containing the portions of a `CommandStartedEvent` the spec tests use for testing.
internal struct TestCommandStartedEvent: Decodable, Matchable {
    let command: Document

    let commandName: String

    let databaseName: String?

    internal enum CodingKeys: String, CodingKey {
        case command, commandName = "command_name", databaseName = "database_name"
    }

    internal enum TopLevelCodingKeys: String, CodingKey {
        case type = "command_started_event"
    }

    internal init(from event: CommandStartedEvent) {
        self.command = event.command
        self.databaseName = event.databaseName
        self.commandName = event.commandName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TopLevelCodingKeys.self)
        let eventContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .type)
        self.command = try eventContainer.decode(Document.self, forKey: .command)
        if let commandName = try eventContainer.decodeIfPresent(String.self, forKey: .commandName) {
            self.commandName = commandName
        } else if let firstKey = self.command.keys.first {
            self.commandName = firstKey
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.commandName,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "commandName not found")
            )
        }
        self.databaseName = try eventContainer.decodeIfPresent(String.self, forKey: .databaseName)
    }

    internal func contentMatches(expected: TestCommandStartedEvent) -> Bool {
        if let expectedDbName = expected.databaseName {
            guard let dbName = self.databaseName, dbName.matches(expected: expectedDbName) else {
                return false
            }
        }
        return self.commandName.matches(expected: expected.commandName)
            && self.command.matches(expected: expected.command)
    }
}

/// Protocol that test cases which configure fail points during their execution conform to.
internal protocol FailPointConfigured: AnyObject {
    /// The fail point currently set, if one exists.
    var activeFailPoint: FailPoint? { get set }
}

extension FailPointConfigured {
    /// Sets the active fail point to the provided fail point and enables it.
    internal func activateFailPoint(_ failPoint: FailPoint) throws {
        self.activeFailPoint = failPoint
        try self.activeFailPoint?.enable()
    }

    /// If a fail point is active, it is disabled and cleared.
    internal func disableActiveFailPoint() {
        if let failPoint = self.activeFailPoint {
            failPoint.disable()
            self.activeFailPoint = nil
        }
    }
}

/// Struct modeling a MongoDB fail point.
///
/// - Note: if a fail point results in a connection being closed / interrupted, libmongoc built in debug mode will print
///         a warning.
internal struct FailPoint: Decodable {
    private var failPoint: Document

    /// The fail point being configured.
    internal var name: String {
        return self.failPoint["configureFailPoint"]?.stringValue ?? ""
    }

    private init(_ document: Document) {
        self.failPoint = document
    }

    public init(from decoder: Decoder) throws {
        self.failPoint = try Document(from: decoder)
    }

    internal func enable() throws {
        var commandDoc = ["configureFailPoint": self.failPoint["configureFailPoint"]!] as Document
        for (k, v) in self.failPoint {
            guard k != "configureFailPoint" else {
                continue
            }

            // Need to convert error codes to int32's due to c driver bug (CDRIVER-3121)
            if k == "data",
                var data = v.documentValue,
                var wcErr = data["writeConcernError"]?.documentValue,
                let code = wcErr["code"] {
                wcErr["code"] = .int32(code.asInt32()!)
                data["writeConcernError"] = .document(wcErr)
                commandDoc["data"] = .document(data)
            } else {
                commandDoc[k] = v
            }
        }
        let client = try MongoClient.makeTestClient()
        try client.db("admin").runCommand(commandDoc)
    }

    internal func disable() {
        do {
            let client = try MongoClient.makeTestClient()
            try client.db("admin").runCommand(["configureFailPoint": .string(self.name), "mode": "off"])
        } catch {
            print("Failed to disable fail point \(self.name): \(error)")
        }
    }

    /// Enum representing the options for the "mode" field of a `configureFailPoint` command.
    public enum Mode {
        case times(Int)
        case alwaysOn
        case off
        case activationProbability(Double)

        internal func toBSON() -> BSON {
            switch self {
            case let .times(i):
                return ["times": BSON(i)]
            case let .activationProbability(d):
                return ["activationProbability": .double(d)]
            default:
                return .string(String(describing: self))
            }
        }
    }

    /// Factory function for creating a `failCommand` failpoint.
    /// Note: enabling a `failCommand` failpoint will override any other `failCommand` failpoint that is currently
    /// enabled.
    /// For more information, see the wiki: https://github.com/mongodb/mongo/wiki/The-%22failCommand%22-fail-point
    public static func failCommand(
        failCommands: [String],
        mode: Mode,
        closeConnection: Bool? = nil,
        errorCode: Int? = nil,
        writeConcernError: Document? = nil
    ) -> FailPoint {
        var data: Document = [
            "failCommands": .array(failCommands.map { .string($0) })
        ]
        if let close = closeConnection {
            data["closeConnection"] = .bool(close)
        }
        if let code = errorCode {
            data["errorCode"] = BSON(code)
        }
        if let writeConcernError = writeConcernError {
            data["writeConcernError"] = .document(writeConcernError)
        }

        let command: Document = [
            "configureFailPoint": "failCommand",
            "mode": mode.toBSON(),
            "data": .document(data)
        ]
        return FailPoint(command)
    }
}

/// Struct representing conditions that a deployment must meet in order for a test file to be run.
internal struct TestRequirement: Decodable {
    private let minServerVersion: ServerVersion?
    private let maxServerVersion: ServerVersion?
    private let topology: [String]?

    /// Determines if the given deployment meets this requirement.
    func isMet(by version: ServerVersion, _ topology: TopologyDescription.TopologyType) -> Bool {
        if let minVersion = self.minServerVersion {
            guard minVersion <= version else {
                return false
            }
        }
        if let maxVersion = self.maxServerVersion {
            guard maxVersion >= version else {
                return false
            }
        }
        if let topologies = self.topology?.map({ TopologyDescription.TopologyType(from: $0) }) {
            guard topologies.contains(topology) else {
                return false
            }
        }
        return true
    }
}

/// Enum representing the contents of deployment before a spec test has been run.
internal enum TestData: Decodable {
    /// Data for multiple collections, with the name of the collection mapping to its contents.
    case multiple([String: [Document]])

    /// The contents of a single collection.
    case single([Document])

    public init(from decoder: Decoder) throws {
        if let array = try? [Document](from: decoder) {
            self = .single(array)
        } else if let document = try? Document(from: decoder) {
            var mapping: [String: [Document]] = [:]
            for (k, v) in document {
                guard let documentArray = v.arrayValue?.asArrayOf(Document.self) else {
                    throw DecodingError.typeMismatch(
                        [Document].self,
                        DecodingError.Context(
                            codingPath: decoder.codingPath,
                            debugDescription: "Expected array of documents, got \(v) instead"
                        )
                    )
                }
                mapping[k] = documentArray
            }
            self = .multiple(mapping)
        } else {
            throw DecodingError.typeMismatch(
                TestData.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Could not decode `TestData`")
            )
        }
    }
}

/// Struct representing the contents of a collection after a spec test has been run.
internal struct CollectionTestInfo: Decodable {
    /// An optional name specifying a collection whose documents match the `data` field of this struct.
    /// If nil, whatever collection used in the test should be used instead.
    let name: String?

    /// The documents found in the collection.
    let data: [Document]
}

/// Struct representing an "outcome" defined in a spec test.
internal struct TestOutcome: Decodable {
    /// Whether an error is expected or not.
    let error: Bool?

    /// The expected result of running the operation associated with this test.
    let result: TestOperationResult?

    /// The expected state of the collection at the end of the test.
    let collection: CollectionTestInfo
}

/// Protocol defining the behavior of an entire spec test file.
internal protocol SpecTestFile: Decodable {
    associatedtype TestType: SpecTest

    /// The name of the file.
    /// This field must be added to the file this test is decoded from.
    var name: String { get }

    /// Server version and topology requirements in order for tests from this file to be run.
    var runOn: [TestRequirement]? { get }

    /// The database to use for testing.
    var databaseName: String { get }

    /// The collection to use for testing.
    var collectionName: String? { get }

    /// Data that should exist in the collection before running any of the tests.
    var data: TestData { get }

    /// List of tests to run in this file.
    var tests: [TestType] { get }
}

extension SpecTestFile {
    /// Populate the database and collection specified by this test file using the provided client.
    internal func populateData(using client: MongoClient) throws {
        let database = client.db(self.databaseName)

        try? database.drop()

        switch self.data {
        case let .single(docs):
            guard let collName = self.collectionName else {
                throw InvalidArgumentError(message: "missing collection name")
            }

            guard !docs.isEmpty else {
                return
            }

            try database.collection(collName).insertMany(docs)
        case let .multiple(mapping):
            for (k, v) in mapping {
                guard !v.isEmpty else {
                    continue
                }
                try database.collection(k).insertMany(v)
            }
        }
    }

    /// Run all the tests specified in this file, optionally specifying keywords that, if included in a test's
    /// description, will cause certain tests to be skipped.
    internal func runTests(parent: FailPointConfigured, skippedTestKeywords: [String] = []) throws {
        let setupClient = try MongoClient.makeTestClient()
        let version = try setupClient.serverVersion()

        if let requirements = self.runOn {
            guard requirements.contains(where: { $0.isMet(by: version, MongoSwiftTestCase.topologyType) }) else {
                fileLevelLog("Skipping tests from file \(self.name), deployment requirements not met.")
                return
            }
        }

        try self.populateData(using: setupClient)

        fileLevelLog("Executing tests from file \(self.name)...")
        for test in self.tests {
            guard skippedTestKeywords.allSatisfy({ !test.description.contains($0) }) else {
                print("Skipping test \(test.description)")
                return
            }
            try test.run(parent: parent, dbName: self.databaseName, collName: self.collectionName)
        }
    }
}

/// Protocol defining the behavior of an individual spec test.
internal protocol SpecTest: Decodable {
    /// The name of the test.
    var description: String { get }

    /// Options used to configure the `MongoClient` used for this test.
    var clientOptions: ClientOptions? { get }

    /// If true, the `MongoClient` for this test should be initialized with multiple mongos seed addresses.
    /// If false or omitted, only a single mongos address should be specified.
    /// This field has no effect for non-sharded topologies.
    var useMultipleMongoses: Bool? { get }

    /// Reason why this test should be skipped, if applicable.
    var skipReason: String? { get }

    /// The optional fail point to configure before running this test.
    /// This option and useMultipleMongoses: true are mutually exclusive.
    var failPoint: FailPoint? { get }

    /// Descriptions of the operations to be run and their expected outcomes.
    var operations: [TestOperationDescription] { get }

    /// List of expected CommandStartedEvents.
    var expectations: [TestCommandStartedEvent]? { get }
}

/// Default implementation of a test execution.
extension SpecTest {
    internal func run(
        parent: FailPointConfigured,
        dbName: String,
        collName: String?
    ) throws {
        guard self.skipReason == nil else {
            print("Skipping test for reason: \(self.skipReason!)")
            return
        }

        print("Executing test: \(self.description)")

        var clientOptions = self.clientOptions ?? ClientOptions(retryReads: true)
        clientOptions.commandMonitoring = self.expectations != nil

        if let failPoint = self.failPoint {
            try parent.activateFailPoint(failPoint)
        }
        defer { parent.disableActiveFailPoint() }

        let client = try MongoClient.makeTestClient(options: clientOptions)
        let db: MongoDatabase = client.db(dbName)
        var collection: MongoCollection<Document>?

        if let collName = collName {
            collection = db.collection(collName)
        }

        let events = try captureCommandEvents(from: client, eventTypes: [.commandStarted]) {
            for operation in self.operations {
                try operation.validateExecution(
                    client: client,
                    database: db,
                    collection: collection,
                    session: nil
                )
            }
        }.map { TestCommandStartedEvent(from: $0 as! CommandStartedEvent) }

        if let expectations = self.expectations {
            expect(events).to(match(expectations), description: self.description)
        }
    }
}
