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

class QrCodeStub: QrCodeProtocol {
    private let _otherUserId: String
    private let _otherDeviceId: String
    private let _flowId: String
    private let _roomId: String?
    private let _weStarted: Bool
    private let _reciprocated: Bool
    private let _hasBeenScanned: Bool
    private let _isDone: Bool
    private let _isCancelled: Bool
    private let _cancelInfo: CancelInfo?
    
    init(
        otherUserId: String = "Bob",
        otherDeviceId: String = "Device2",
        flowId: String = "123",
        roomId: String? = "ABC",
        weStarted: Bool = false,
        reciprocated: Bool = false,
        hasBeenScanned: Bool = false,
        isDone: Bool = false,
        isCancelled: Bool = false,
        cancelInfo: CancelInfo? = nil
    ) {
        _otherUserId = otherUserId
        _otherDeviceId = otherDeviceId
        _flowId = flowId
        _roomId = roomId
        _weStarted = weStarted
        _reciprocated = reciprocated
        _hasBeenScanned = hasBeenScanned
        _isDone = isDone
        _isCancelled = isCancelled
        _cancelInfo = cancelInfo
    }
    
    func otherUserId() -> String {
        _otherUserId
    }
    
    func otherDeviceId() -> String {
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
    
    func isDone() -> Bool {
        _isDone
    }
    
    func isCancelled() -> Bool {
        _isCancelled
    }
    
    func cancelInfo() -> MatrixSDKCrypto.CancelInfo? {
        _cancelInfo
    }
    
    func reciprocated() -> Bool {
        _reciprocated
    }
    
    func hasBeenScanned() -> Bool {
        _hasBeenScanned
    }
    
    func confirm() -> MatrixSDKCrypto.ConfirmVerificationResult? {
        nil
    }
    
    func cancel(cancelCode: String) -> MatrixSDKCrypto.OutgoingVerificationRequest? {
        nil
    }
    
    func generateQrCode() -> String? {
        nil
    }
    
    func setChangesListener(listener: QrCodeListener) {
    }
    
    func state() -> QrCodeState {
        .started
    }
}

