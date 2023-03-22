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

import MatrixSDKCrypto

class VerificationRequestStub: VerificationRequestProtocol {
    
    var _otherUserId: String
    var _otherDeviceId: String
    var _flowId: String
    var _roomId: String?
    var _weStarted: Bool
    var _isReady: Bool
    var _isPassive: Bool
    var _isDone: Bool
    var _isCancelled: Bool
    var _cancelInfo: CancelInfo?
    var _theirMethods: [String]
    var _ourMethods: [String]
    
    var shouldFail: Bool = false
    
    init(
        otherUserId: String = "Bob",
        otherDeviceId: String = "Device2",
        flowId: String = "123",
        roomId: String? = "ABC",
        weStarted: Bool = true,
        isReady: Bool = false,
        isPassive: Bool = false,
        isDone: Bool = false,
        isCancelled: Bool = false,
        cancelInfo: CancelInfo? = nil,
        theirMethods: [String] = ["sas"],
        ourMethods: [String] = ["sas"]
    ) {
        _otherUserId = otherUserId
        _otherDeviceId = otherDeviceId
        _flowId = flowId
        _roomId = roomId
        _weStarted = weStarted
        _isReady = isReady
        _isPassive = isPassive
        _isDone = isDone
        _isCancelled = isCancelled
        _cancelInfo = cancelInfo
        _theirMethods = theirMethods
        _ourMethods = ourMethods
    }
    
    func otherUserId() -> String {
        _otherUserId
    }
    
    func otherDeviceId() -> String? {
        _otherDeviceId
    }
    
    func flowId() -> String {
        _flowId
    }
    
    func roomId() -> String? {
        _roomId
    }
    
    func weStarted() -> Bool {
        _weStarted
    }
    
    func isReady() -> Bool {
        _isReady
    }
    
    func isDone() -> Bool {
        _isDone
    }
    
    func isPassive() -> Bool {
        _isPassive
    }
    
    func isCancelled() -> Bool {
        _isCancelled
    }
    
    func cancelInfo() -> MatrixSDKCrypto.CancelInfo? {
        _cancelInfo
    }
    
    func theirSupportedMethods() -> [String]? {
        _theirMethods
    }
    
    func ourSupportedMethods() -> [String]? {
        _ourMethods
    }
    
    func accept(methods: [String]) -> OutgoingVerificationRequest? {
        shouldFail ? nil : .inRoom(requestId: "", roomId: "2", eventType: "", content: "")
        
    }
    
    func startSasVerification() throws -> StartSasResult? {
        nil
    }
    
    func startQrVerification() throws -> QrCode? {
        nil
    }
    
    func scanQrCode(data: String) -> ScanResult? {
        nil
    }
    
    func cancel() -> OutgoingVerificationRequest? {
        shouldFail ? nil : .inRoom(requestId: "", roomId: "2", eventType: "", content: "")
    }
    
    func setChangesListener(listener: VerificationRequestListener) {
        
    }
    
    func state() -> VerificationRequestState {
        .requested
    }
}
