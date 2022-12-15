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

/// Dummy implementation of background crypto that does nothing and is unable
/// to decrypt notification.
///
/// Note: This is a temporary class to be used with foreground Crypto V2 which
/// is not currently multi-process safe and thus only one process can be
/// decrypting events.
class MXDummyBackgroundCrypto: MXBackgroundCrypto {
    enum Error: Swift.Error {
        case unableToDecrypt
    }
    
    func handleSyncResponse(_ syncResponse: MXSyncResponse) {
    }
    
    func canDecryptEvent(_ event: MXEvent) -> Bool {
        false
    }
    
    func decryptEvent(_ event: MXEvent) throws {
        throw Error.unableToDecrypt
    }
}

#endif
