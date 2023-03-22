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
@testable import MatrixSDK

class MXAnalyticsDestinationUnitTests: XCTestCase {
    enum Error: Swift.Error {
        case sampleError
    }
    
    class DelegateSpy: NSObject, MXAnalyticsDelegate {
        func trackDuration(_ milliseconds: Int, name: MXTaskProfileName, units: UInt) {
        }
        
        func startDurationTracking(forName name: String, operation: String) -> StopDurationTracking {
            {}
        }
        
        func trackCallStarted(withVideo isVideo: Bool, numberOfParticipants: Int, incoming isIncoming: Bool) {
        }
        
        func trackCallEnded(withDuration duration: Int, video isVideo: Bool, numberOfParticipants: Int, incoming isIncoming: Bool) {
        }
        
        func trackCallError(with reason: __MXCallHangupReason, video isVideo: Bool, numberOfParticipants: Int, incoming isIncoming: Bool) {
        }
        
        func trackCreatedRoom(asDM isDM: Bool) {
        }
        
        func trackJoinedRoom(asDM isDM: Bool, isSpace: Bool, memberCount: UInt) {
        }
        
        func trackContactsAccessGranted(_ granted: Bool) {
        }
        
        func trackComposerEvent(inThread: Bool, isEditing: Bool, isReply: Bool, startsThread: Bool) {
        }
        
        var spyIssue: String?
        var spyDetails: [String: Any]?
        func trackNonFatalIssue(_ issue: String, details: [String: Any]?) {
            spyIssue = issue
            spyDetails = details
        }
    }
    
    var delegate: DelegateSpy!
    var destination: MXAnalyticsDestination!
    
    override func setUp() {
        delegate = DelegateSpy()
        MXSDKOptions.sharedInstance().analyticsDelegate = delegate
        destination = MXAnalyticsDestination()
    }
    
    func track(msg: String, context: Any? = nil) {
        _ = destination.send(.error, msg: msg, thread: "", file: "", function: "", line: 0, context: context)
    }
    
    func test_tracksNoContext() {
        track(msg: "Sample", context: nil)
        
        XCTAssertEqual(delegate.spyIssue, "Sample")
        XCTAssertNil(delegate.spyDetails)
    }
    
    func test_tracksDictionaryContext() {
        track(msg: "ABC", context: [
            "A": 1,
            "B": 2
        ])
        
        XCTAssertEqual(delegate.spyIssue, "ABC")
        XCTAssertEqual(delegate.spyDetails as? NSDictionary, ["A": 1, "B": 2])
    }
    
    func test_tracksErrorContext() {
        track(msg: "ABC", context: Error.sampleError)
        
        XCTAssertEqual(delegate.spyIssue, "ABC")
        XCTAssertEqual(delegate.spyDetails as? NSDictionary, ["error": Error.sampleError])
    }
    
    func test_tracksNSErrorContext() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown)
        
        track(msg: "ABC", context: error)
        
        XCTAssertEqual(delegate.spyIssue, "ABC")
        XCTAssertEqual(delegate.spyDetails as? NSDictionary, ["error": error])
    }
    
    func test_doesNotTrackCancellationError() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        
        track(msg: "XYZ", context: error)
        
        XCTAssertNil(delegate.spyIssue)
        XCTAssertNil(delegate.spyDetails)
    }
    
    func test_tracksOtherContext() {
        track(msg: "XYZ", context: 1)
        
        XCTAssertEqual(delegate.spyIssue, "XYZ")
        XCTAssertEqual(delegate.spyDetails as? NSDictionary, ["context": "1"])
    }
}
