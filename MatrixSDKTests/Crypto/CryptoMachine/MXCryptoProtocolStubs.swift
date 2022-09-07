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

#if DEBUG && os(iOS)

import MatrixSDKCrypto

class CryptoIdentityStub: MXCryptoIdentity {
    var userId: String = "Alice"
    var deviceId: String = "ABCD"
    
    var deviceCurve25519Key: String? {
        return nil
    }
    
    var deviceEd25519Key: String? {
        return nil
    }
}

class DevicesSourceStub: CryptoIdentityStub, MXCryptoDevicesSource {
    var devices = [String: [String: Device]]()
    
    func device(userId: String, deviceId: String) -> Device? {
        return devices[userId]?[deviceId]
    }
    
    func devices(userId: String) -> [Device] {
        return devices[userId]?.map { $0.value } ?? []
    }
}

@available(iOS 13.0.0, *)
class UserIdentitySourceStub: CryptoIdentityStub, MXCryptoUserIdentitySource {
    var identities = [String: UserIdentity]()
    func userIdentity(userId: String) -> UserIdentity? {
        return identities[userId]
    }
    
    var verification = [String: Bool]()
    func isUserVerified(userId: String) -> Bool {
        return verification[userId] ?? false
    }
    
    func downloadKeys(users: [String]) async throws {
        
    }
}

@available(iOS 13.0.0, *)
class CryptoCrossSigningStub: CryptoIdentityStub, MXCryptoCrossSigning {
    var stubbedStatus = CrossSigningStatus(
        hasMaster: false,
        hasSelfSigning: false,
        hasUserSigning: false
    )
    func crossSigningStatus() -> CrossSigningStatus {
        return stubbedStatus
    }
    
    func bootstrapCrossSigning(authParams: [AnyHashable : Any]) async throws {
    }
    
    var stubbedIdentities = [String: UserIdentity]()
    func userIdentity(userId: String) -> UserIdentity? {
        stubbedIdentities[userId]
    }
    
    var stubbedVerifiedUsers = Set<String>()
    func isUserVerified(userId: String) -> Bool {
        return stubbedVerifiedUsers.contains(userId)
    }
    
    func downloadKeys(users: [String]) async throws {
    }
}

@available(iOS 13.0.0, *)
class CryptoVerificationStub: CryptoIdentityStub {
    var stubbedRequests = [String: VerificationRequest]()
    var stubbedTransactions = [String: Verification]()
    var stubbedErrors = [String: Error]()
    var stubbedEmojis = [String: [Int]]()
}

@available(iOS 13.0.0, *)
extension CryptoVerificationStub: MXCryptoVerificationRequesting {
    func requestSelfVerification(methods: [String]) async throws -> VerificationRequest {
        .stub()
    }
    
    func requestVerification(userId: String, roomId: String, methods: [String]) async throws -> VerificationRequest {
        .stub()
    }
    
    func verificationRequest(userId: String, flowId: String) -> VerificationRequest? {
        return stubbedRequests[flowId]
    }
    
    func acceptVerificationRequest(userId: String, flowId: String, methods: [String]) async throws {
        if let error = stubbedErrors[flowId] {
            throw error
        }
    }
    
    func cancelVerification(userId: String, flowId: String, cancelCode: String) async throws {
        if let error = stubbedErrors[flowId] {
            throw error
        }
    }
}

@available(iOS 13.0.0, *)
extension CryptoVerificationStub: MXCryptoVerifying {
    func verification(userId: String, flowId: String) -> Verification? {
        return stubbedTransactions[flowId]
    }
    
    func confirmVerification(userId: String, flowId: String) async throws {
    }
}

@available(iOS 13.0.0, *)
extension CryptoVerificationStub: MXCryptoSASVerifying {
    func startSasVerification(userId: String, flowId: String) async throws -> Sas {
        .stub()
    }
    
    func acceptSasVerification(userId: String, flowId: String) async throws {
    }
    
    func emojiIndexes(sas: Sas) throws -> [Int] {
        stubbedEmojis[sas.flowId] ?? []
    }
}

#endif
