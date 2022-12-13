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

/// Placehoder QR transaction generated in case we cannot start a QR verification flow
/// (the other device cannot scan our code) but we may be able to scan theirs
class MXPlaceholderQRCodeTransaction: NSObject, MXQRCodeTransaction {
    let state: MXQRCodeTransactionState
    let qrCodeData: MXQRCodeData?
    let transactionId: String
    let transport: MXKeyVerificationTransport
    let isIncoming: Bool
    let otherUserId: String
    let otherDeviceId: String
    let reasonCancelCode: MXTransactionCancelCode?
    let error: Error?
    let dmRoomId: String?
    let dmEventId: String?
    
    private let log = MXNamedLog(name: "MXPlaceholderQRCodeTransaction")
    
    init(otherUserId: String, otherDeviceId: String, flowId: String, roomId: String?) {
        self.state = .unknown
        self.qrCodeData = nil
        self.transactionId = flowId
        self.transport = roomId != nil ? .directMessage : .toDevice
        self.isIncoming = false
        self.otherUserId = otherUserId
        self.otherDeviceId = otherDeviceId
        self.reasonCancelCode = nil
        self.error = nil
        self.dmRoomId = roomId
        self.dmEventId = roomId != nil ? flowId : nil
    }
    
    func cancel(with code: MXTransactionCancelCode) {
        log.failure("Should not be called")
    }
    
    func cancel(with code: MXTransactionCancelCode, success: @escaping () -> Void, failure: @escaping (Error) -> Void) {
        log.failure("Should not be called")
    }
    
    func userHasScannedOtherQrCodeData(_ otherQRCodeData: MXQRCodeData) {
        log.failure("Should not be called")
    }
    
    func otherUserScannedMyQrCode(_ otherUserScanned: Bool) {
        log.failure("Should not be called")
    }
}
