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

extension VerificationRequest {
    static func stub(
        otherUserId: String = "Bob",
        otherDeviceId: String = "Device2",
        flowId: String = "123",
        roomId: String = "ABC",
        weStarted: Bool = true,
        isReady: Bool = false,
        isPassive: Bool = false,
        isDone: Bool = false,
        isCancelled: Bool = false,
        cancelInfo: CancelInfo? = nil,
        theirMethods: [String] = ["sas"],
        ourMethods: [String] = ["sas"]
    ) -> VerificationRequest {
        return .init(
            otherUserId: otherUserId,
            otherDeviceId: otherDeviceId,
            flowId: flowId,
            roomId: roomId,
            weStarted: weStarted,
            isReady: isReady,
            isPassive: isPassive,
            isDone: isDone,
            isCancelled: isCancelled,
            cancelInfo: cancelInfo,
            theirMethods: theirMethods,
            ourMethods: ourMethods
        )
    }
}

#endif
