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

#if DEBUG

import MatrixSDKCrypto

extension QrCode {
    static func stub(
        otherUserId: String = "Bob",
        otherDeviceId: String = "Device2",
        flowId: String = "123",
        roomId: String = "ABC",
        weStarted: Bool = true,
        otherSideScanned: Bool = false,
        hasBeenConfirmed: Bool = false,
        reciprocated: Bool = false,
        isDone: Bool = false,
        isCancelled: Bool = false,
        cancelInfo: CancelInfo? = nil
    ) -> QrCode {
        return .init(
            otherUserId: otherUserId,
            otherDeviceId: otherDeviceId,
            flowId: flowId,
            roomId: roomId,
            weStarted: weStarted,
            otherSideScanned: otherSideScanned,
            hasBeenConfirmed: hasBeenConfirmed,
            reciprocated: reciprocated,
            isDone: isDone,
            isCancelled: isCancelled,
            cancelInfo: cancelInfo
        )
    }
}

#endif
