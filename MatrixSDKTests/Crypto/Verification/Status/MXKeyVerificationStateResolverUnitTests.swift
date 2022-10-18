// 
// Copyright 2022 The Matrix.org Foundation C.I.C
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

import Foundation
import XCTest
@testable import MatrixSDK

class MXKeyVerificationStateResolverUnitTests: XCTestCase {
    class AggregationsStub: MXAggregations {
        var stubbedEvents = [MXEvent]()
        override func referenceEvents(
            forEvent eventId: String,
            inRoom roomId: String,
            from: String?,
            limit: Int,
            success: @escaping (MXAggregationPaginatedResponse) -> Void,
            failure: @escaping (Error) -> Void
        ) -> MXHTTPOperation {
            success(.init(originalEvent: MXEvent(), chunk: stubbedEvents, nextBatch: nil))
            return MXHTTPOperation()
        }
    }
    
    var aggregations: AggregationsStub!
    var resolver: MXKeyVerificationStateResolver!
    override func setUp() {
        aggregations = AggregationsStub()
        resolver = MXKeyVerificationStateResolver(myUserId: "Alice", aggregations: aggregations)
    }
    
    func verificationState() async throws -> MXKeyVerificationState {
        // FlowId and RoomId do not matter for the purpose of this test suite
        return try await resolver.verificationState(flowId: "", roomId: "")
    }
    
    func test_defaultState() async throws {
        let state = try await verificationState()
        XCTAssertEqual(state, .transactionStarted)
    }
    
    func test_cancelledByMeState() async throws {
        aggregations.stubbedEvents = [
            MXEvent.fixture(
                type: kMXEventTypeStringKeyVerificationCancel,
                sender: "Alice",
                content: [
                    "code": "m.user"
                ]
            )
        ]
        let state = try await verificationState()
        XCTAssertEqual(state, .transactionCancelledByMe)
    }
    
    func test_cancelledState() async throws {
        aggregations.stubbedEvents = [
            MXEvent.fixture(
                type: kMXEventTypeStringKeyVerificationCancel,
                sender: "Bob",
                content: [
                    "code": "m.user"
                ]
            )
        ]
        let state = try await verificationState()
        XCTAssertEqual(state, .transactionCancelled)
    }
    
    func test_expiredState() async throws {
        aggregations.stubbedEvents = [
            MXEvent.fixture(
                type: kMXEventTypeStringKeyVerificationCancel,
                content: [
                    "code": "m.timeout"
                ]
            )
        ]
        let state = try await verificationState()
        XCTAssertEqual(state, .requestExpired)
    }
    
    func test_failedState() async throws {
        aggregations.stubbedEvents = [
            MXEvent.fixture(
                type: kMXEventTypeStringKeyVerificationCancel
            )
        ]
        let state = try await resolver.verificationState(flowId: "", roomId: "")
        XCTAssertEqual(state, .transactionFailed)
    }
    
    func test_verifiedState() async throws {
        aggregations.stubbedEvents = [
            MXEvent.fixture(
                type: kMXEventTypeStringKeyVerificationDone
            )
        ]
        let state = try await verificationState()
        XCTAssertEqual(state, .verified)
    }
    
    func test_readyState() async throws {
        aggregations.stubbedEvents = [
            MXEvent.fixture(
                type: kMXEventTypeStringKeyVerificationReady
            )
        ]
        
        let state = try await verificationState()
        XCTAssertEqual(state, .requestReady)
    }
    
    func test_overrideReadyState() async throws {
        aggregations.stubbedEvents = [
            MXEvent.fixture(
                type: kMXEventTypeStringKeyVerificationReady
            ),
            MXEvent.fixture(
                type: kMXEventTypeStringKeyVerificationCancel
            ),
        ]
        
        let state = try await verificationState()
        XCTAssertEqual(state, .transactionFailed)
    }
    
}
