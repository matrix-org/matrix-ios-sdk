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

import Foundation

@testable import MatrixSDK

class MXSyncResponseUnitTests: XCTestCase {
    
    /// Tests merging dictionaries by checking a should-be-updated value (`next_batch`) and should-be-cumulated value (`to_device.events`).
    func testMergingDictionaries() {
        let numberOfDictionaries = 10
        let nextBatchPrefix = "s72595_4483_1934_"
        let deviceIdPrefix = "XYZABCDE_"
        var dictionaries: [NSDictionary] = []
        
        for i in 1...numberOfDictionaries {
            let response: [AnyHashable: Any] = [
                "next_batch": "\(nextBatchPrefix)\(i)",
                "rooms": [
                    "leave": [],
                    "join": [],
                    "invite": []
                ],
                "to_device": [
                    "events": [
                        [
                            "sender": "@alice:example.com",
                            "type": "m.new_device",
                            "content": [
                                "device_id": "\(deviceIdPrefix)\(i)",
                                "rooms": [
                                    "!726s6s6q:example.com"
                                ]
                            ]
                        ]
                    ]
                ]
            ]
            
            dictionaries.append(NSDictionary(dictionary: response))
        }
        
        //  make sure all dictionaries processed
        XCTAssertEqual(dictionaries.count, numberOfDictionaries)
        
        var merged: NSDictionary!
        
        for dictionary in dictionaries {
            if let tmpMerged = merged {
                merged = tmpMerged + dictionary
            } else {
                merged = dictionary
            }
        }
        
        guard let nextBatch = merged["next_batch"] as? String else {
            XCTFail("Response dictionary corrupted")
            return
        }
        
        //  check next batch
        XCTAssertEqual(nextBatch, "\(nextBatchPrefix)\(numberOfDictionaries)")
        
        guard let toDevice = merged["to_device"] as? [AnyHashable: Any],
              let events = toDevice["events"] as? [Any] else {
            XCTFail("Response dictionary corrupted")
            return
        }
        
        //  check to-device events count
        XCTAssertEqual(events.count, numberOfDictionaries)
        
        guard let event = events.last as? [AnyHashable: Any],
              let content = event["content"] as? [AnyHashable: Any],
              let deviceId = content["device_id"] as? String else {
            XCTFail("Response dictionary corrupted")
            return
        }
        
        //  check last to-device event content
        XCTAssertEqual(deviceId, "\(deviceIdPrefix)\(numberOfDictionaries)")
    }
    
    /// Tests merging arrays by cumulating one-item arrays and at the end by checking total number of items in the merge result.
    func testMergingArrays() {
        let numberOfArrays = 10
        let itemPrefix = "Item_"
        var arrays: [NSArray] = []
        
        for i in 1...numberOfArrays {
            arrays.append(NSArray(array: ["\(itemPrefix)\(i)"]))
        }
        
        //  make sure all arrays processed
        XCTAssertEqual(arrays.count, numberOfArrays)
        
        var merged: NSArray!
        
        for array in arrays {
            if let tmpMerged = merged {
                merged = tmpMerged + array
            } else {
                merged = array
            }
        }
        
        //  check item count
        XCTAssertEqual(merged.count, numberOfArrays)
        
        guard let lastItem = merged.lastObject as? String else {
            XCTFail("Corrupted array")
            return
        }
        
        XCTAssertEqual(lastItem, "\(itemPrefix)\(numberOfArrays)")
    }
}
