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

class MXDehydrationSwiftTests: XCTestCase, MXKeyProviderDelegate {
    
    // MARK: - Properties
    
    private let sectionFormat = "\n\n\n\n\n\n\n\n========================================================================\n%@\n========================================================================\n\n\n\n\n\n\n\n"
    private var matrixSDKTestsData: MatrixSDKTestsData!
    private var matrixSDKTestsE2EData: MatrixSDKTestsE2EData!

    private var aliceSessionToClose: MXSession?
    private var bobSessionToClose: MXSession?
    private var retainedObjects: [NSObject]!
    private var dehydrationKey: MXKeyData!

    // MARK: - Setup

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        matrixSDKTestsData = MatrixSDKTestsData()
        matrixSDKTestsE2EData = MatrixSDKTestsE2EData(matrixSDKTestsData: matrixSDKTestsData)
        
        let key = "6fXK17pQFUrFqOnxt3wrqz8RHkQUT9vQ".data(using: .utf8) ?? Data()
        dehydrationKey = MXRawDataKey(key: key)
        MXKeyProvider.sharedInstance().delegate = self
        
        retainedObjects = []
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        aliceSessionToClose?.close()
        aliceSessionToClose = nil
        
        bobSessionToClose?.close()
        bobSessionToClose = nil

        matrixSDKTestsData = nil;
        matrixSDKTestsE2EData = nil;
        
        retainedObjects.removeAll()
    }
    
    // MARK: - Tests
    
    // Check device dehydration
    // - Have e2e Alice
    // - Alice creates a dehydrated device
    // - Alice downloads their own devices keys
    // -> Alice must see their dehydrated device
    func testDehydrateDevice() {
        // - Have e2e Alice
        matrixSDKTestsE2EData.doE2ETestWithAlice(inARoom: self) { (mxSession, roomId, expectation) in
            
            guard let session = mxSession else {
                XCTFail("Session shouldn't be nil.")
                expectation?.fulfill()
                return
            }

            // - Alice creates a dehydrated device
            session.dehydrationService.dehydrateDevice(success: { (dehydratedDeviceId) in
                
                guard let dehydratedDeviceId = dehydratedDeviceId else {
                    XCTFail("dehydratedDeviceId shouldn't be nil.")
                    expectation?.fulfill()
                    return
                }

                // - Alice downloads her own devices keys
                mxSession?.crypto.downloadKeys([session.myUserId], forceDownload: true, success: { (usersDevicesInfoMap, crossSigningKeysMap) in
                    
                    // -> Alice must see their dehydrated device
                    XCTAssertEqual(usersDevicesInfoMap?.deviceIds(forUser: session.myUserId)?.count, 2)
                    
                    let dehydratedDevice = usersDevicesInfoMap?.object(forDevice: dehydratedDeviceId, forUser: session.myUserId)
                    XCTAssertNotNil(dehydratedDevice)
                    XCTAssertEqual(dehydratedDevice?.deviceId, dehydratedDeviceId)
                    
                    expectation?.fulfill()

                }, failure: { (error) in
                    XCTFail("The request should not fail - NSError: \(String(describing: error))")
                    expectation?.fulfill()
                })
            }, failure: { (error) in
                XCTFail("The request should not fail - NSError: \(error)")
                expectation?.fulfill()
            })
        }
    }
    
    // Check that others can see a dehydrated device
    // - Alice and Bob are in an e2e room
    // - Bob creates a dehydrated device and logs out
    // - Alice download Bob's devices keys
    // -> Alice must see Bob's dehydrated device
    func testDehydrateDeviceSeenByOther() {
        // - Alice and Bob are in an e2e room
        matrixSDKTestsE2EData.doE2ETestWithAliceAndBob(inARoom: self, cryptedBob: true, warnOnUnknowDevices: false) { (aliceSession, bobSession, roomId, expectation) in
            
            guard let aliceSession = aliceSession else {
                XCTFail("aliceSession shouldn't be nil.")
                expectation?.fulfill()
                return
            }

            guard let bobSession = bobSession else {
                XCTFail("bobSession shouldn't be nil.")
                expectation?.fulfill()
                return
            }
            
            guard let bobUserId = bobSession.myUserId else {
                XCTFail("bobUserId shouldn't be nil.")
                expectation?.fulfill()
                return
            }

            // - Bob creates a dehydrated device and logs out
            bobSession.dehydrationService.dehydrateDevice { (bobDehydratedDeviceId) in
                
                guard let bobDehydratedDeviceId = bobDehydratedDeviceId else {
                    XCTFail("bobDehydratedDeviceId shouldn't be nil.")
                    expectation?.fulfill()
                    return
                }

                DispatchQueue.main.async {
                    bobSession.logout { (response) in
                        guard response.isSuccess else {
                            XCTFail("The request should not fail - NSError: \(String(describing: response.error))")
                            expectation?.fulfill()
                            return
                        }
                    }
                    
                    // - Alice download Bob's devices keys
                    aliceSession.crypto.downloadKeys([bobUserId], forceDownload: true) { (usersDevicesInfoMap, crossSigningKeysMap) in
                        
                        NSLog("[MXCryptoTest] User devices: \(usersDevicesInfoMap?.deviceIds(forUser: bobUserId))")

                        // -> Alice must see Bob's dehydrated device
                        XCTAssertEqual(usersDevicesInfoMap?.deviceIds(forUser: bobUserId)?.count, 1)
                        
                        let bobDehydratedDevice = usersDevicesInfoMap?.object(forDevice: bobDehydratedDeviceId, forUser: bobUserId)
                        XCTAssertNotNil(bobDehydratedDevice)
                        XCTAssertEqual(bobDehydratedDevice?.deviceId, bobDehydratedDeviceId)
                        
                        expectation?.fulfill()

                    } failure: { (error) in
                        XCTFail("The request should not fail - NSError: \(String(describing: error))")
                        expectation?.fulfill()
                        return
                    }
                }
            } failure: { (error) in
                XCTFail("The request should not fail - NSError: \(error)")
                expectation?.fulfill()
            }

        }
    }
    
    func testClaimDehydratedDevice() {
        MXSDKOptions.sharedInstance().enableCryptoWhenStartingMXSession = false
        
        matrixSDKTestsData.doMXRestClientTest(withBob: self) { (bobRestClient, expectation) in
            guard let mxSession = MXSession(matrixRestClient: bobRestClient) else {
                XCTFail("mxSession shouldn't be nil.")
                expectation?.fulfill()
                return
            }
            
            self.retain(object: mxSession)
            
            mxSession.dehydrationService.rehydrateDevice {
                expectation?.fulfill()
            } failure: { (error) in
                XCTFail("The request should not fail - NSError: \(error)")
                expectation?.fulfill()
            }
        }
    }
    
    func testDehydrateDeviceAndClaimDehydratedDevice() {
        MXSDKOptions.sharedInstance().enableCryptoWhenStartingMXSession = true
        
        matrixSDKTestsE2EData.doE2ETestWithAlice(inARoom: self) { (aliceSession, roomId, expectation) in
            guard let aliceSession = aliceSession else {
                XCTFail("aliceSession shouldn't be nil.")
                expectation?.fulfill()
                return
            }
            
            let aliceSessionDevice = aliceSession.myDeviceId
            aliceSession.dehydrationService.dehydrateDevice { (dehydratedDeviceId) in
                guard let dehydratedDeviceId = dehydratedDeviceId else {
                    XCTFail("dehydratedDeviceId shouldn't be nil.")
                    expectation?.fulfill()
                    return
                }
                
                DispatchQueue.main.async {
                    self.matrixSDKTestsData.loginUser(onANewDevice:self, credentials: nil, withPassword: MXTESTS_ALICE_PWD, sessionToLogout: aliceSession, newSessionStore: nil, startNewSession: false, e2e: true) { (aliceSession2) in
                        guard let aliceSession2 = aliceSession2 else {
                            XCTFail("aliceSession2 shouldn't be nil.")
                            expectation?.fulfill()
                            return
                        }
                        
                        let aliceSession2Device = aliceSession2.myDeviceId
                        
                        aliceSession2.dehydrationService.rehydrateDevice {
                            XCTAssertNotEqual(aliceSessionDevice, aliceSession2Device)
                            XCTAssertNotEqual(aliceSession2Device, dehydratedDeviceId)
                            XCTAssertNotEqual(aliceSession2.myDeviceId, aliceSession2Device)
                            
                            XCTAssertEqual(aliceSession2.myDeviceId, dehydratedDeviceId)
                            
                            aliceSession2.start { (response) in
                                guard response.isSuccess else {
                                    XCTFail("The request should not fail - NSError: \(String(describing: response.error))")
                                    expectation?.fulfill()
                                    return
                                }
                                
                                XCTAssertNotNil(aliceSession2.crypto);
//                                XCTAssertEqual(aliceSession2.crypto?.myDevice.deviceId, dehydratedDeviceId)
//                                XCTAssertEqual(aliceSession2.crypto?.store.deviceId, dehydratedDeviceId)
                            }
                        } failure: { (error) in
                            XCTFail("The request should not fail - NSError: \(error)")
                            expectation?.fulfill()
                        }
                    }
                }
            } failure: { (error) in
                XCTFail("The request should not fail - NSError: \(error)")
                expectation?.fulfill()
            }

        }
    }

    // MARK: - Private methods
    
    private func retain(object: NSObject) {
        retainedObjects.append(object)
    }

    // MARK: - MXKeyProviderDelegate
    
    func isEncryptionAvailableForData(ofType dataType: String) -> Bool {
        return dataType == MXDehydrationServiceKeyDataType
    }
    
    func hasKeyForData(ofType dataType: String) -> Bool {
        return dataType == MXDehydrationServiceKeyDataType
    }
    
    func keyDataForData(ofType dataType: String) -> MXKeyData? {
        return dehydrationKey
    }
    
}
