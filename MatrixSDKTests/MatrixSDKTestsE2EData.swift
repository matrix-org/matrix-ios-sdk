// 
// Copyright 2023 The Matrix.org Foundation C.I.C
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

extension MatrixSDKTestsE2EData {
    enum Error: Swift.Error {
        case missingDependencies
    }
    
    class Environment {
        let session: MXSession
        let roomId: String
        
        init(session: MXSession, roomId: String) {
            self.session = session
            self.roomId = roomId
        }
        
        @MainActor
        func close() {
            session.close()
        }
    }

    @MainActor
    func startE2ETest() async throws -> Environment {
        
        return try await withCheckedThrowingContinuation { continuation in
            doE2ETestWithAlice(inARoom: nil) { session, roomId, _ in
                guard let session = session, let roomId = roomId else {
                    continuation.resume(throwing: Error.missingDependencies)
                    return
                }
                continuation.resume(returning: .init(session: session, roomId: roomId))
            }
        }
    }
}
