import MongoSwift
import Nimble
import TestsCommon

extension WriteConcern {
    /// Initialize a new `WriteConcern` from a `Document`. We can't
    /// use `decode` because the format is different in spec tests
    /// ("journal" instead of "j", etc.)
    fileprivate init(_ doc: Document) throws {
        let j = doc["journal"]?.boolValue

        var w: W?
        if let wtag = doc["w"]?.stringValue {
            w = wtag == "majority" ? .majority : .tag(wtag)
        } else if let wInt = doc["w"]?.asInt32() {
            w = .number(wInt)
        }

        let wt = doc["wtimeoutMS"]?.asInt64()

        try self.init(journal: j, w: w, wtimeoutMS: wt)
    }
}

class ReadWriteConcernSpecTests: MongoSwiftTestCase {
    func testConnectionStrings() throws {
        let testFiles = try retrieveSpecTestFiles(
            specName: "read-write-concern",
            subdirectory: "connection-string",
            asType: Document.self
        )
        for (_, asDocument) in testFiles {
            let tests: [Document] = asDocument["tests"]!.arrayValue!.compactMap { $0.documentValue }
            for test in tests {
                let description: String = try test.get("description")
                // skipping because C driver does not comply with these; see CDRIVER-2621
                if description.lowercased().contains("wtimeoutms") { continue }
                let uri: String = try test.get("uri")
                let valid: Bool = try test.get("valid")
                if valid {
                    let client = try MongoClient(uri)
                    if let readConcern = test["readConcern"]?.documentValue {
                        let rc = try BSONDecoder().decode(ReadConcern.self, from: readConcern)
                        if rc.isDefault {
                            expect(client.readConcern).to(beNil())
                        } else {
                            expect(client.readConcern).to(equal(rc))
                        }
                    } else if let writeConcern = test["writeConcern"]?.documentValue {
                        let wc = try WriteConcern(writeConcern)
                        if wc.isDefault {
                            expect(client.writeConcern).to(beNil())
                        } else {
                            expect(client.writeConcern).to(equal(wc))
                        }
                    }
                } else {
                    expect(try MongoClient(uri)).to(throwError(errorType: InvalidArgumentError.self))
                }
            }
        }
    }

    func testDocuments() throws {
        let encoder = BSONEncoder()
        let testFiles = try retrieveSpecTestFiles(
            specName: "read-write-concern",
            subdirectory: "document",
            asType: Document.self
        )

        for (_, asDocument) in testFiles {
            let tests = asDocument["tests"]!.arrayValue!.compactMap { $0.documentValue }
            for test in tests {
                let valid: Bool = try test.get("valid")
                if let rcToUse = test["readConcern"]?.documentValue {
                    let rc = try BSONDecoder().decode(ReadConcern.self, from: rcToUse)

                    let isDefault: Bool = try test.get("isServerDefault")
                    expect(rc.isDefault).to(equal(isDefault))

                    let expected: Document = try test.get("readConcernDocument")
                    if expected == [:] {
                        expect(try encoder.encode(rc)).to(beNil())
                    } else {
                        expect(try encoder.encode(rc)).to(equal(expected))
                    }
                } else if let wcToUse = test["writeConcern"]?.documentValue {
                    if valid {
                        let wc = try WriteConcern(wcToUse)

                        let isAcknowledged: Bool = try test.get("isAcknowledged")
                        expect(wc.isAcknowledged).to(equal(isAcknowledged))

                        let isDefault: Bool = try test.get("isServerDefault")
                        expect(wc.isDefault).to(equal(isDefault))

                        var expected: Document = try test.get("writeConcernDocument")
                        if expected == [:] {
                            expect(try encoder.encode(wc)).to(beNil())
                        } else {
                            if let wtimeoutMS = expected["wtimeout"] {
                                expected["wtimeout"] = .int64(wtimeoutMS.asInt64()!)
                            }
                            expect(try encoder.encode(wc)).to(sortedEqual(expected))
                        }
                    } else {
                        expect(try WriteConcern(wcToUse)).to(throwError(errorType: InvalidArgumentError.self))
                    }
                }
            }
        }
    }
}
