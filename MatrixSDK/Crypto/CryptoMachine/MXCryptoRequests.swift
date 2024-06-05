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

/// Convenience class to delegate network requests originating in Rust crypto module
/// to the native REST API client
struct MXCryptoRequests {
    private let restClient: MXRestClient
    private let queryScheduler: MXKeysQueryScheduler<MXKeysQueryResponseRaw>
    
    init(restClient: MXRestClient) {
        self.restClient = restClient
        self.queryScheduler = .init { users in
            try await performCallbackRequest { completion in
                _ = restClient.downloadKeysByChunkRaw(
                    forUsers: users,
                    token: nil,
                    success: {
                        completion(.success($0))
                    }, failure: {
                        completion(.failure($0 ?? Error.unknownError))
                    })
            }
        }
    }
    
    func sendToDevice(request: ToDeviceRequest) async throws {
        try await performCallbackRequest {
            restClient.sendDirectToDevice(
                payload: .init(
                    eventType: request.eventType,
                    contentMap: request.contentMap,
                    transactionId: nil,
                    addMessageId: request.addMessageId
                ),
                completion: $0
            )
        }
    }
    
    func uploadKeys(request: UploadKeysRequest) async throws -> MXKeysUploadResponse {
        try await performCallbackRequest {
            restClient.uploadKeys(
                request.deviceKeys,
                oneTimeKeys: request.oneTimeKeys,
                fallbackKeys: request.fallbackKeys,
                forDevice: request.deviceId,
                completion: $0
            )
        }
    }
    
    func uploadSigningKeys(request: UploadSigningKeysRequest, authParams: [AnyHashable: Any]) async throws {
        let keys = try request.jsonKeys()
        return try await performCallbackRequest { continuation in
            restClient.uploadDeviceSigningKeys(
                keys,
                authParams: authParams,
                success: {
                    continuation(.success(()))
                },
                failure: {
                    continuation(.failure($0 ?? Error.unknownError))
                }
            )
        }
    }
    
    func uploadSignatures(request: SignatureUploadRequest) async throws {
        let signatures = try request.jsonSignature()
        return try await performCallbackRequest { continuation in
            restClient.uploadKeySignatures(
                signatures,
                success: {
                    continuation(.success(()))
                },
                failure: {
                    continuation(.failure($0 ?? Error.unknownError))
                }
            )
        }
    }
    
    func queryKeys(users: [String]) async throws -> MXKeysQueryResponseRaw {
        try await queryScheduler.query(users: Set(users))
    }
    
    func claimKeys(request: ClaimKeysRequest) async throws -> MXKeysClaimResponse {
        try await performCallbackRequest {
            restClient.claimOneTimeKeys(for: request.devices, completion: $0)
        }
    }
    
    @MainActor
    // Calling methods on `MXRoom` has various state side effects so should be called on the main thread
    func roomMessage(request: RoomMessageRequest) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            var event: MXEvent?
            request.room.sendEvent(
                MXEventType(identifier: request.eventType),
                content: request.content,
                localEcho: &event) { response in
                    switch response {
                    case .success(let value):
                        continuation.resume(returning: value)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
        }
    }
    
    func backupKeys(request: KeysBackupRequest) async throws -> [AnyHashable: Any] {
        try await performCallbackRequest { continuation in
            restClient.sendKeysBackup(
                request.keysBackupData,
                version: request.version,
                success: {
                    continuation(.success($0 ?? [:]))
                }, failure: {
                    continuation(.failure($0 ?? Error.unknownError))
                }
            )
        }
    }
}

/// Convenience structs mapping Rust requests to data for native REST API requests
extension MXCryptoRequests {
    enum Error: Swift.Error {
        case cannotCreateRequest
        case unknownError
    }
    
    struct ToDeviceRequest {
        let eventType: String
        let contentMap: MXUsersDevicesMap<NSDictionary>
        let addMessageId: Bool
        
        init(eventType: String, body: String, addMessageId: Bool) throws {
            guard
                let json = MXTools.deserialiseJSONString(body) as? [String: [String: NSDictionary]],
                let contentMap = MXUsersDevicesMap<NSDictionary>(map: json)
            else {
                throw Error.cannotCreateRequest
            }
            
            self.eventType = eventType
            self.contentMap = contentMap
            self.addMessageId = addMessageId
        }
    }
    
    struct UploadKeysRequest {
        let deviceKeys: [String: Any]?
        let oneTimeKeys: [String: Any]?
        let fallbackKeys: [String: Any]?
        let deviceId: String
        
        init(body: String, deviceId: String) throws {
            guard let json = MXTools.deserialiseJSONString(body) as? [String: Any] else {
                throw Error.cannotCreateRequest
            }
            
            self.deviceKeys = json["device_keys"] as? [String : Any]
            self.oneTimeKeys = json["one_time_keys"] as? [String : Any]
            self.fallbackKeys = json["fallback_keys"] as? [String : Any]
            self.deviceId = deviceId
        }
    }
    
    struct ClaimKeysRequest {
        let devices: MXUsersDevicesMap<NSString>
        
        init(oneTimeKeys: [String: [String: String]]) {
            let devices = MXUsersDevicesMap<NSString>()
            for (userId, values) in oneTimeKeys {
                let userDevices = values.mapValues { $0 as NSString }
                devices.setObjects(userDevices, forUser: userId)
            }
            self.devices = devices
        }
    }
    
    struct RoomMessageRequest {
        let room: MXRoom
        let eventType: String
        let content: [String: Any]
        
        init(room: MXRoom, eventType: String, content: String) throws {
            guard let json = MXTools.deserialiseJSONString(content) as? [String: Any] else {
                throw Error.cannotCreateRequest
            }
            self.room = room
            self.eventType = eventType
            self.content = json
        }
    }
    
    struct KeysBackupRequest {
        let version: String
        let keysBackupData: MXKeysBackupData
        
        init(version: String, rooms: String) throws {
            self.version = version
            guard
                let json = MXTools.deserialiseJSONString(rooms),
                let data = MXKeysBackupData(fromJSON: ["rooms": json])
            else {
                throw Error.cannotCreateRequest
            }
            self.keysBackupData = data
        }
    }
}

extension UploadSigningKeysRequest {
    func jsonKeys() throws -> [AnyHashable: Any] {
        guard
            let masterKeyJson = MXTools.deserialiseJSONString(masterKey),
            let selfKeyJson = MXTools.deserialiseJSONString(selfSigningKey),
            let userKeyJson = MXTools.deserialiseJSONString(userSigningKey)
        else {
            throw MXCryptoRequests.Error.cannotCreateRequest
        }
        
        return [
            "master_key": masterKeyJson,
            "self_signing_key": selfKeyJson,
            "user_signing_key": userKeyJson
        ]
    }
}

extension SignatureUploadRequest {
    func jsonSignature() throws -> [AnyHashable: Any] {
        guard let signatures = MXTools.deserialiseJSONString(body) as? [AnyHashable: Any] else {
            throw MXCryptoRequests.Error.cannotCreateRequest
        }
        return signatures
    }
}
