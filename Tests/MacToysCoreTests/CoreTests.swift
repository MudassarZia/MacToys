import XCTest
@testable import MacToysCore

final class TransformTests: XCTestCase {
    func testCSVQuotedCommasNewlinesAndEscapes() throws {
        XCTAssertEqual(try CSV.parse("name,note\r\nAda,\"hello, \"\"world\"\"\nagain\"\r\n"), [["name", "note"], ["Ada", "hello, \"world\"\nagain"]])
    }
    func testCSVRoundTrip() throws {
        let values = ["", "a,b", "\"quote\"", "line\nbreak", "emoji 🛠", "trailing "]
        XCTAssertEqual(try CSV.parse(values.map(CSV.escape).joined(separator: ",")), [values])
    }
    func testMalformedCSV() {
        for text in ["a,\"unclosed", "a,un\"quoted", "\"closed\"garbage,b"] { XCTAssertThrowsError(try CSV.parse(text)) }
    }
    func testCSVJSONRejectsDuplicateAndMismatchedHeaders() {
        for text in ["a,a\n1,2", "a,b\n1", ",b\n1,2"] { XCTAssertThrowsError(try TextTransform.csvJSON.apply(text)) }
    }
    func testJSONTransformRoundtrip() throws {
        let csv = "name,note\nAda,\"hello, world\"\nGrace,compiler"
        let json = try TextTransform.csvJSON.apply(csv)
        XCTAssertEqual(try TextTransform.jsonCSV.apply(json), csv)
    }
    func testJSONNestedTypes() throws {
        XCTAssertEqual(try TextTransform.jsonCSV.apply("[{\"a\":true,\"b\":null,\"c\":[1,2]}]"), "a,b,c\ntrue,,\"[1,2]\"")
    }
    func testJSONFragmentsAndInvalidInput() throws {
        XCTAssertEqual(try TextTransform.compactJSON.apply(" {\"z\": 1, \"a\": 2} "), "{\"a\":2,\"z\":1}")
        XCTAssertEqual(try TextTransform.json.apply("true"), "true")
        XCTAssertThrowsError(try TextTransform.json.apply("nope"))
    }
    func testMarkdownEscaping() throws {
        XCTAssertEqual(try TextTransform.markdown.apply("a,b\n1,\"x|y\nnext\""), "| a | b |\n| --- | --- |\n| 1 | x\\|y<br>next |")
    }
    func testEncodingRoundTrips() throws {
        let text = "Hello 🌎 + / ? & 日本語"
        XCTAssertEqual(try TextTransform.urlDecode.apply(TextTransform.urlEncode.apply(text)), text)
        XCTAssertEqual(try TextTransform.unbase64.apply(TextTransform.base64.apply(text)), text)
        XCTAssertEqual(try TextTransform.urlEncode.apply("a+b c"), "a%2Bb%20c")
        XCTAssertThrowsError(try TextTransform.unbase64.apply("invalid!"))
        XCTAssertThrowsError(try TextTransform.urlDecode.apply("%XY"))
    }
    func testLineTransforms() throws {
        XCTAssertEqual(try TextTransform.unique.apply("a\nb\na\nb\nc"), "a\nb\nc")
        XCTAssertEqual(try TextTransform.trim.apply(" a \n b\t"), "a\nb")
        XCTAssertEqual(try TextTransform.sort.apply("c\na\nb"), "a\nb\nc")
        XCTAssertEqual(try TextTransform.htmlEscape.apply("<&\"'>"), "&lt;&amp;&quot;&#39;&gt;")
    }
    func testEnvironmentQuotesMetacharactersLiterally() throws {
        let output = try Shell.environment("GREETING=hello world\nVALUE='$(touch /tmp/never-run)'`id`\nEMPTY=\n# comment")
        XCTAssertTrue(output.contains("export GREETING='hello world'"))
        XCTAssertTrue(output.contains("export VALUE=''\\''$(touch /tmp/never-run)'\\''`id`'"))
        XCTAssertTrue(output.contains("export EMPTY=''"))
    }
    func testEnvironmentRejectsInvalidKeys() {
        for input in ["1FOO=x", "FOO BAR=x", "A;id=x", "MISSING", "A=x\0"] { XCTAssertThrowsError(try Shell.environment(input)) }
    }
    func testZoneValidation() {
        XCTAssertTrue(Zone.defaults.allSatisfy(\.valid))
        XCTAssertFalse(Zone(name: "bad", x: 0.9, y: 0, width: 0.5, height: 1).valid)
        XCTAssertFalse(Zone(name: "bad", x: .nan, y: 0, width: 0.5, height: 1).valid)
        XCTAssertFalse(Zone(name: "bad", x: 0, y: 0, width: 0, height: 1).valid)
    }
}

final class RenameTests: XCTestCase {
    var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func file(_ name: String, _ content: String = "original") throws -> URL {
        let url = directory.appendingPathComponent(name); try content.write(to: url, atomically: true, encoding: .utf8); return url
    }
    func plan(_ files: [URL], _ search: String, _ replacement: String, regex: Bool = false, sensitive: Bool = true, extensions: Bool = false) throws -> [RenameItem] {
        try Renamer.plan(files: files, search: search, replacement: replacement, regex: regex, caseSensitive: sensitive, includeExtension: extensions)
    }
    func testBatchAndUndoPreserveContents() throws {
        let a = try file("old-1.txt", "A"), b = try file("old-2.txt", "B")
        let items = try plan([a,b], "old", "new")
        let undo = try Renamer.execute(items)
        XCTAssertEqual(try String(contentsOf: items[0].destination), "A")
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        _ = try Renamer.execute(undo)
        XCTAssertEqual(try String(contentsOf: a), "A"); XCTAssertEqual(try String(contentsOf: b), "B")
    }
    func testExistingDestinationNeverOverwritten() throws {
        let a = try file("old.txt"), b = try file("new.txt", "valuable")
        XCTAssertThrowsError(try plan([a], "old", "new"))
        XCTAssertEqual(try String(contentsOf: b), "valuable")
    }
    func testDuplicateOutputsRejected() throws {
        let a = try file("a1.txt"), b = try file("a2.txt")
        XCTAssertThrowsError(try plan([a,b], "[12]", "", regex: true))
    }
    func testRegexCaptureAndUnicode() throws {
        let a = try file("café-42.txt")
        let items = try plan([a], "(.*)-(\\d+)", "$2-$1", regex: true)
        XCTAssertEqual(items[0].destination.lastPathComponent, "42-café.txt")
    }
    func testLiteralReplacementDoesNotInterpretGroups() throws {
        let a = try file("old.txt")
        XCTAssertEqual(try plan([a], "old", "$1")[0].destination.lastPathComponent, "$1.txt")
    }
    func testExtensionOption() throws {
        let a = try file("a.txt")
        XCTAssertEqual(try plan([a], "txt", "md")[0].destination, a)
        XCTAssertEqual(try plan([a], "txt", "md", extensions: true)[0].destination.lastPathComponent, "a.md")
    }
    func testPathTraversalRejected() throws {
        let a = try file("old.txt")
        for replacement in ["../outside", "nested/file", "bad:name", "bad\0name"] { XCTAssertThrowsError(try plan([a], "old", replacement)) }
    }
    func testRevalidateBeforeApply() throws {
        let a = try file("old.txt")
        let items = try plan([a], "old", "new")
        let b = try file("new.txt", "appeared after preview")
        XCTAssertThrowsError(try Renamer.execute(items))
        XCTAssertEqual(try String(contentsOf: a), "original"); XCTAssertEqual(try String(contentsOf: b), "appeared after preview")
    }
    func testUndoCollisionDoesNotOverwrite() throws {
        let a = try file("old.txt")
        let undo = try Renamer.execute(plan([a], "old", "new"))
        _ = try file("old.txt", "new unrelated file")
        XCTAssertThrowsError(try Renamer.execute(undo))
        XCTAssertEqual(try String(contentsOf: a), "new unrelated file")
    }
    func testInvalidExpressionAndEmptySearch() throws {
        let a = try file("old.txt")
        XCTAssertThrowsError(try plan([a], "[", "x", regex: true))
        XCTAssertThrowsError(try plan([a], "", "x"))
    }
    func testReplacedSourceRejected() throws {
        let source = try file("old.txt")
        let items = try plan([source], "old", "new")
        let replacement = try file("replacement.txt", "different file")
        try FileManager.default.removeItem(at: source)
        try FileManager.default.moveItem(at: replacement, to: source)
        XCTAssertThrowsError(try Renamer.execute(items))
        XCTAssertEqual(try String(contentsOf: source), "different file")
    }
}
