// 
// Copyright 2021 The Matrix.org Foundation C.I.C
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import XCTest

@testable import MatrixSDK

class MXStoreRoomListDataManagerUnitTests: XCTestCase {
    
    private enum Constants {
        static var credentials: MXCredentials {
            let result = MXCredentials(homeServer: "localhost",
                                       userId: "@some_user_id:some_domain.com",
                                       accessToken: "some_access_token")
            result.deviceId = "some_device_id"
            return result
        }
        static let messageText: String = "Hello there!"
    }
    
    override class func setUp() {
        MXSDKOptions.sharedInstance().roomListDataManagerClass = MXStoreRoomListDataManager.self
    }
    
    private var basicFetchOptions: MXRoomListDataFetchOptions {
        let filterOptions = MXRoomListDataFilterOptions(showAllRoomsInHomeSpace: false)
        let sortOptions = MXRoomListDataSortOptions(missedNotificationsFirst: false, unreadMessagesFirst: false)
        return MXRoomListDataFetchOptions(filterOptions: filterOptions,
                                          sortOptions: sortOptions,
                                          paginationOptions: .none,
                                          async: false)
    }
    
    //  MARK - Tests
    
    func testPaginationOptionsInit() {
        let options1 = MXRoomListDataPaginationOptions.none
        let options2 = MXRoomListDataPaginationOptions(rawValue: MXRoomListDataPaginationOptions.NoneValue)
        XCTAssertEqual(options1, options2, "Pagination options should be equal")
        
        let options3 = MXRoomListDataPaginationOptions.default
        let options4 = MXRoomListDataPaginationOptions(rawValue: MXRoomListDataPaginationOptions.DefaultValue)
        XCTAssertEqual(options3, options4, "Pagination options should be equal")
        
        let options5 = MXRoomListDataPaginationOptions(rawValue: 5)
        let options6 = MXRoomListDataPaginationOptions.custom(5)
        XCTAssertEqual(options5, options6, "Pagination options should be equal")
    }
    
    func testFilterOptionsInit() {
        let filterOptions = MXRoomListDataFilterOptions(showAllRoomsInHomeSpace: false)
        XCTAssertTrue(filterOptions.dataTypes.isEmpty, "Default data types should be empty")
        XCTAssertEqual(filterOptions.notDataTypes, [.hidden, .conferenceUser, .space], "Default not data types should be provided")
        XCTAssertFalse(filterOptions.onlySuggested, "Default filter options should not include onlySuggested")
        XCTAssertNil(filterOptions.query, "Default filter options should not include query")
        XCTAssertNil(filterOptions.space, "Default filter options should not include space")
    }
    
    func testSortOptionsInit() {
        let missedNotificationsFirst = true
        let unreadMessagesFirst = true
        let sortOptions = MXRoomListDataSortOptions(missedNotificationsFirst: missedNotificationsFirst,
                                                    unreadMessagesFirst: unreadMessagesFirst)
        XCTAssertEqual(missedNotificationsFirst, sortOptions.missedNotificationsFirst, "Sort options should persist missedNotificationsFirst")
        XCTAssertEqual(unreadMessagesFirst, sortOptions.unreadMessagesFirst, "Sort options should persist unreadMessagesFirst")
        XCTAssertTrue(sortOptions.invitesFirst, "Default sort options should include invitesFirst")
        XCTAssertTrue(sortOptions.sentStatus, "Default sort options should include sentStatus")
        XCTAssertTrue(sortOptions.lastEventDate, "Default sort options should include lastEventDate")
        XCTAssertFalse(sortOptions.favoriteTag, "Default sort options should not include favoriteTag")
        XCTAssertTrue(sortOptions.suggested, "Default sort options should include suggested")
    }
    
    func testFetchOptionsInit() {
        let fetchOptions = self.basicFetchOptions
        XCTAssertEqual(fetchOptions.async, false, "Fetch options should not include async")
        XCTAssertEqual(fetchOptions.paginationOptions, .none, "Default fetch options should not include pagination")
        XCTAssertNil(fetchOptions.fetcher, "Fetch options should not include fetcher without initializing a fetcher")
    }
    
    func testDataManagerInitStandalone() {
        let manager = MXStoreRoomListDataManager()
        let restClient = MXRestClient(credentials:  Constants.credentials, unrecognizedCertificateHandler: nil, persistentTokenDataHandler: nil, unauthenticatedHandler: nil)
        guard let session = MXSession(matrixRestClient: restClient) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        wait { expectation in
            session.setStore(MXMemoryStore(), completion: { response in
                switch response {
                case .success:
                    manager.configure(withSession: session)
                    XCTAssertEqual(manager.session, session, "Manager should persist session")
                    let fetchOptions = self.basicFetchOptions
                    let fetcher = manager.fetcher(withOptions: fetchOptions)
                    XCTAssertEqual(fetcher.fetchOptions, fetchOptions, "Fetch options should be persisted in fetcher")
                    
                    session.close()
                    expectation.fulfill()
                case .failure(let error):
                    XCTFail("Failed to setup test conditions: \(error)")
                    return
                }
            })
        }
    }
    
    func testDataManagerInitFromSession() {
        let restClient = MXRestClient(credentials:  Constants.credentials, unrecognizedCertificateHandler: nil, persistentTokenDataHandler: nil, unauthenticatedHandler: nil)
        guard let session = MXSession(matrixRestClient: restClient) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        XCTAssertNil(session.roomListDataManager, "Room list data manager should be created after setting the store")
        
        wait { expectation in
            session.setStore(MXMemoryStore(), completion: { response in
                switch response {
                case .success:
                    guard let manager = session.roomListDataManager else {
                        XCTFail("Failed to setup test conditions")
                        return
                    }
                    XCTAssertEqual(manager.session, session, "Manager should persist session")
                    let fetchOptions = self.basicFetchOptions
                    let fetcher = manager.fetcher(withOptions: fetchOptions)
                    XCTAssertEqual(fetcher.fetchOptions, fetchOptions, "Fetch options should be persisted in fetcher")
                    
                    session.close()
                    expectation.fulfill()
                case .failure(let error):
                    XCTFail("Failed to setup test conditions: \(error)")
                    return
                }
            })
        }
    }
    
    func testFilterDataTypes() {
        generateDefaultFetcher { fetcher in
            //  clear not data types first
            fetcher.fetchOptions.filterOptions.notDataTypes = []
            XCTAssertEqual(fetcher.data?.counts.numberOfRooms, 90, "Fetcher should update data to 90 (all) rooms")
            
            //  filter to only invited
            fetcher.fetchOptions.filterOptions.dataTypes = .invited
            XCTAssertEqual(fetcher.data?.counts.numberOfRooms, 10, "Fetcher should update data to 10 invited rooms")
            XCTAssertEqual(fetcher.data?.counts.numberOfInvitedRooms, 10, "Fetcher should update data to 10 invited rooms")
            
            //  filter to invited and direct
            fetcher.fetchOptions.filterOptions.dataTypes = [.invited, .direct]
            XCTAssertEqual(fetcher.data?.counts.numberOfRooms, 20, "Fetcher should update data to 20 rooms (10 invited + 10 direct)")
            XCTAssertEqual(fetcher.data?.counts.numberOfInvitedRooms, 10, "Fetcher should update data to 10 invited rooms")
        }
    }
    
    func testFilterQuery() {
        generateDefaultFetcher { fetcher in
            //  clear not data types first
            fetcher.fetchOptions.filterOptions.notDataTypes = []
            XCTAssertEqual(fetcher.data?.counts.numberOfRooms, 90, "Fetcher should update data to 90 (all) rooms")
            
            //  update query
            fetcher.fetchOptions.filterOptions.query = "9"
            XCTAssertEqual(fetcher.data?.counts.numberOfRooms, 10, "Fetcher should update data to 10 rooms (all rooms suffixing with '9')")
            
            //  update query
            fetcher.fetchOptions.filterOptions.query = "Room 9"
            XCTAssertEqual(fetcher.data?.counts.numberOfRooms, 2, "Fetcher should update data to only 2 rooms (Room 9 and Room 90)")
            
            //  update query
            fetcher.fetchOptions.filterOptions.query = "Room 90"
            XCTAssertEqual(fetcher.data?.counts.numberOfRooms, 1, "Fetcher should update data to only 1 rooms")
            
            //  update query
            fetcher.fetchOptions.filterOptions.query = "Room 91"
            XCTAssertEqual(fetcher.data?.counts.numberOfRooms, 0, "Fetcher should update data to 0 rooms")
            
            //  reset query
            fetcher.fetchOptions.filterOptions.query = nil
            XCTAssertEqual(fetcher.data?.counts.numberOfRooms, 90, "Fetcher should update data to 90 (all) rooms")
            
            //  set query as empty
            fetcher.fetchOptions.filterOptions.query = ""
            XCTAssertEqual(fetcher.data?.counts.numberOfRooms, 90, "Fetcher should update data to 90 (all) rooms")
        }
    }
    
    func testSortOptionsInvitesFirst() {
        generateDefaultFetcher { fetcher in
            guard let rooms = fetcher.data?.rooms else {
                XCTFail("Failed to setup test conditions")
                return
            }
            
            //  check first 10 rooms are invited
            for index in 0..<10 {
                let summary = rooms[index]
                XCTAssertTrue(summary.isTyped(.invited), "First 10 rooms must be invited rooms")
            }
        }
    }
    
    func testSortOptionsLastEventDate() {
        generateDefaultFetcher { fetcher in
            fetcher.fetchOptions.filterOptions.notDataTypes = []
            fetcher.fetchOptions.sortOptions.invitesFirst = false
            
            guard let rooms = fetcher.data?.rooms else {
                XCTFail("Failed to setup test conditions")
                return
            }
            
            //  check first 10 rooms are untyped
            for index in 0..<10 {
                let summary = rooms[index]
                XCTAssertTrue(summary.dataTypes.isEmpty, "First 10 rooms must be untyped rooms, according to last event date")
            }
            
            let typesToCheck = MXRoomSummaryDataTypes.all.reversed()
            
            var start = 10
            for type in typesToCheck {
                //  check second 10 rooms are untyped
                for index in start..<start+10 {
                    let summary = rooms[index]
                    XCTAssertTrue(summary.isTyped(type), "nth 10 rooms must be typed rooms, according to last event date")
                }
                start += 10
            }
        }
    }
    
    private func generateDefaultFetcher(_ completion: @escaping (MXRoomListDataFetcher) -> Void) {
        let restClient = MXRestClient(credentials:  Constants.credentials, unrecognizedCertificateHandler: nil, persistentTokenDataHandler: nil, unauthenticatedHandler: nil)
        guard let session = MXSession(matrixRestClient: restClient) else {
            XCTFail("Failed to setup test conditions")
            return
        }
        let store = MXMemoryStore()
        let roomSummaries = generateMockRoomSummaries()
        XCTAssertEqual(roomSummaries.count, 90, "Generator must generate 90 rooms in total")
        //  insert all rooms into the store
        for summary in roomSummaries {
            store.roomSummaryStore.storeSummary(summary)
        }
        
        self.wait { expectation in
            session.setStore(store, completion: { response in
                switch response {
                case .success:
                    guard let manager = session.roomListDataManager else {
                        XCTFail("Failed to setup test conditions")
                        return
                    }
                    let fetcher = manager.fetcher(withOptions: self.basicFetchOptions)
                    fetcher.paginate()
                    
                    XCTAssertEqual(fetcher.data?.counts.numberOfRooms, 60, "Fetcher should fetch all rooms except types: [.hidden, .conferenceUser, .space]")
                    
                    completion(fetcher)
                    
                    store.deleteAllData()
                    session.close()
                    expectation.fulfill()
                case .failure(let error):
                    XCTFail("Failed to setup test conditions: \(error)")
                    return
                }
            })
        }
    }
    
    /// Generates 10 rooms per each type. Generates 90 rooms by default. Sorted by data types and lastEventDate ascending.
    private func generateMockRoomSummaries(numberOfRoomsPerType: [Int] = Array(repeating: 10, count: MXRoomSummaryDataTypes.all.count),
                                           numberOfUntyped: Int = 10) -> [MXRoomSummaryProtocol] {
        var result: [MockRoomSummary] = []
        
        for (index, numberOfRooms) in numberOfRoomsPerType.enumerated() {
            let safeIndex = index % MXRoomSummaryDataTypes.all.count
            let typed = (0..<numberOfRooms).map({ _ in MockRoomSummary.generate(withTypes: MXRoomSummaryDataTypes.all[safeIndex]) })
            result.append(contentsOf: typed)
        }
        
        let untyped = (0..<numberOfUntyped).map({ _ in MockRoomSummary.generate() })
        result.append(contentsOf: untyped)
        
        //  rename rooms by index
        for (index, summary) in result.enumerated() {
            summary.displayName = "Room \(index + 1)"
            if let event = MXEvent(fromJSON: [
                "event_id": MXTools.generateTransactionId() as Any,
                "room_id": summary.roomId,
                "type": kMXEventTypeStringRoomMessage,
                "origin_server_ts": Date().timeIntervalSince1970 - TimeInterval(result.count - index),
                "content": [
                    "type": kMXMessageTypeText,
                    "content": "Message \(index+1)"
                ]
            ]) {
                summary.lastMessage = MXRoomLastMessage(event: event)
            }
        }
        
        return result
    }
    
    private func wait(_ timeout: TimeInterval = 5, _ block: @escaping (XCTestExpectation) -> Void) {
        let waiter = XCTWaiter()
        let expectation = XCTestExpectation(description: "Async operation expectation")
        block(expectation)
        waiter.wait(for: [expectation], timeout: timeout)
    }
    
}

fileprivate extension MXRoomSummaryDataTypes {
    
    static let all: [MXRoomSummaryDataTypes] = [.invited, .favorited, .direct, .lowPriority, .serverNotice, .hidden, .space, .conferenceUser]
    
}
