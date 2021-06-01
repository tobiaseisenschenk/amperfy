import XCTest
@testable import Amperfy

class AuthParserTest: XCTestCase {
    
    var cdHelper: CoreDataHelper!
    var library: LibraryStorage!
    var xmlData: Data!
    var ampacheUrlCreator: MOCK_AmpacheUrlCreator!
    var syncWave: SyncWave!

    override func setUp() {
        cdHelper = CoreDataHelper()
        let context = cdHelper.createInMemoryManagedObjectContext()
        cdHelper.clearContext(context: context)
        library = LibraryStorage(context: context)
        xmlData = getTestFileData(name: "handshake")
        ampacheUrlCreator = MOCK_AmpacheUrlCreator()
        syncWave = library.createSyncWave()
    }

    override func tearDown() {
    }
    
    func testParsing() {
        let parserDelegate = AuthParserDelegate()
        let parser = XMLParser(data: xmlData)
        parser.delegate = parserDelegate
        parser.parse()

        XCTAssertNil(parserDelegate.error)
        XCTAssertEqual(parserDelegate.serverApiVersion, "5.0.0")
        guard let handshake = parserDelegate.authHandshake else { XCTFail(); return }
        XCTAssertEqual(handshake.token, "cfj3f237d563f479f5223k23189dbb34")
        XCTAssertEqual(handshake.sessionExpire, "2021-03-31T18:16:10+10:00".asIso8601Date)
        XCTAssertEqual(handshake.libraryChangeDates.dateOfLastAdd, "2021-03-31T13:32:27+10:00".asIso8601Date)
        XCTAssertEqual(handshake.libraryChangeDates.dateOfLastClean, "2021-03-31T17:15:18+10:00".asIso8601Date)
        XCTAssertEqual(handshake.libraryChangeDates.dateOfLastUpdate, "2021-03-31T17:15:25+10:00".asIso8601Date)
        XCTAssertEqual(handshake.songCount, 55)
        XCTAssertEqual(handshake.artistCount, 16)
        XCTAssertEqual(handshake.albumCount, 8)
        XCTAssertEqual(handshake.genreCount, 6)
        XCTAssertEqual(handshake.playlistCount, 19)
        XCTAssertEqual(handshake.videoCount, 2)
    }

}