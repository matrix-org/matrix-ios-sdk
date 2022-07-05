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

#if DEBUG && os(iOS)

import MatrixSDKCrypto

/// Wrapper around Rust-based `OlmMachine`, providing a more convenient API.
///
/// Two main responsibilities of the `MXCryptoMachine` are:
/// - mapping to and from raw strings passed into the Rust machine
/// - performing network requests and marking them as completed on behalf of the Rust machine
@available(iOS 13.0.0, *)
class MXCryptoMachine {
    actor RoomQueues {
        private var queues = [String: MXTaskQueue]()
        
        func getQueue(for roomId: String) -> MXTaskQueue {
            let queue = queues[roomId] ?? MXTaskQueue()
            queues[roomId] = queue
            return queue
        }
    }
    
    private static let storeFolder = "MXCryptoStore"
    
    enum Error: Swift.Error {
        case invalidStorage
        case invalidEvent
        case nothingToEncrypt
    }
    
    var deviceCurve25519Key: String? {
        guard let key = machine.identityKeys()["curve25519"] else {
            log(error: "Cannot get device curve25519 key")
            return nil
        }
        return key
    }
    
    var deviceEd25519Key: String? {
        guard let key = machine.identityKeys()["ed25519"] else {
            log(error: "Cannot get device ed25519 key")
            return nil
        }
        return key
    }
    
    private let machine: OlmMachine
    private let requests: MXCryptoRequests
    private let serialQueue = MXTaskQueue()
    private var roomQueues = RoomQueues()

    init(userId: String, deviceId: String, restClient: MXRestClient) throws {
        requests = MXCryptoRequests(restClient: restClient)
    
        let url = try Self.storeURL(for: userId)
        machine = try OlmMachine(
            userId: userId,
            deviceId: deviceId,
            path: url.path,
            passphrase: nil
        )
        
        setLogger(logger: self)
    }
    
    private static func storeURL(for userId: String) throws -> URL {
        let container: URL
        if let sharedContainerURL = FileManager.default.applicationGroupContainerURL() {
            container = sharedContainerURL
        } else if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            container = url
        } else {
            throw Error.invalidStorage
        }

        return container
            .appendingPathComponent(Self.storeFolder)
            .appendingPathComponent(userId)
    }
    
    func handleSyncResponse(
        toDevice: MXToDeviceSyncResponse?,
        deviceLists: MXDeviceListResponse?,
        deviceOneTimeKeysCounts: [String: NSNumber],
        unusedFallbackKeys: [String]?
    ) throws {
        let events = toDevice?.jsonString() ?? "[]"
        let deviceChanges = DeviceLists(
            changed: deviceLists?.changed ?? [],
            left: deviceLists?.left ?? []
        )
        let keyCounts = deviceOneTimeKeysCounts.compactMapValues { $0.int32Value }
        
        let result = try machine.receiveSyncChanges(
            events: events,
            deviceChanges: deviceChanges,
            keyCounts: keyCounts,
            unusedFallbackKeys: unusedFallbackKeys
        )
        
        if let result = MXTools.deserialiseJSONString(result) as? [String: Any], !result.isEmpty {
            log(error: "Result processing not implemented \(result)")
        }
    }
    
    func completeSync() async throws {
        try await serialQueue.sync { [weak self] in
            try await self?.processOutgoingRequests()
        }
    }
    
    func shareRoomKeysIfNecessary(roomId: String, users: [String]) async throws {
        try await serialQueue.sync { [weak self] in
            try await self?.updateTrackedUsers(users: users)
            try await self?.getMissingSessions(users: users)
        }
        
        let roomQueue = await roomQueues.getQueue(for: roomId)
        try await roomQueue.sync { [weak self] in
            try await self?.shareRoomKey(roomId: roomId, users: users)
        }
    }
    
    func encrypt(_ content: [AnyHashable: Any], roomId: String, eventType: String, users: [String]) async throws -> [String: Any] {
        guard let content = MXTools.serialiseJSONObject(content) else {
            throw Error.nothingToEncrypt
        }
        
        try await shareRoomKeysIfNecessary(roomId: roomId, users: users)
        let event = try machine.encrypt(roomId: roomId, eventType: eventType as String, content: content)
        return MXTools.deserialiseJSONString(event) as? [String: Any] ?? [:]
    }
    
    func decryptEvent(_ event: MXEvent) throws -> MXEventDecryptionResult {
        guard let roomId = event.roomId, let event = event.jsonString() else {
            throw Error.invalidEvent
        }
        
        let result = try machine.decryptRoomEvent(event: event, roomId: roomId)
        return try MXEventDecryptionResult(event: result)
    }
    
    // MARK: - Requests
    
    private func handleRequest(_ request: Request) async throws {
        switch request {
        case .toDevice(let requestId, let eventType, let body):
            try await requests.sendToDevice(request: .init(eventType: eventType, body: body))
            try markRequestAsSent(requestId: requestId, requestType: .toDevice)

        case .keysUpload(let requestId, let body):
            let response = try await requests.uploadKeys(request: .init(body: body, deviceId: machine.deviceId()))
            try markRequestAsSent(requestId: requestId, requestType: .keysUpload, response: response)
            
        case .keysQuery(let requestId, let users):
            let response = try await requests.queryKeys(users: users)
            try markRequestAsSent(requestId: requestId, requestType: .keysQuery, response: response)
            
        case .keysClaim(let requestId, let oneTimeKeys):
            let response = try await requests.claimKeys(request: .init(oneTimeKeys: oneTimeKeys))
            try markRequestAsSent(requestId: requestId, requestType: .keysClaim, response: response)

        case .keysBackup:
            log(error: "Keys backup not implemented")
            
        case .roomMessage:
            log(error: "Room message not implemented")
            
        case .signatureUpload:
            log(error: "Signature upload not implemented")
        }
    }
    
    private func markRequestAsSent(requestId: String, requestType: RequestType, response: MXJSONModel? = nil) throws {
        try self.machine.markRequestAsSent(requestId: requestId, requestType: requestType, response: response?.jsonString() ?? "")
    }
    
    // MARK: - Private
    
    private func updateTrackedUsers(users: [String]) async throws {
        machine.updateTrackedUsers(users: users)
        try await processOutgoingRequests()
    }
    
    private func getMissingSessions(users: [String]) async throws {
        guard
            let request = try machine.getMissingSessions(users: users),
            case .keysClaim = request
        else {
            return
        }
        try await handleRequest(request)
    }
    
    private func shareRoomKey(roomId: String, users: [String]) async throws {
        let requests = try machine.shareRoomKey(roomId: roomId, users: users)
        await withThrowingTaskGroup(of: Void.self) { [weak self] group in
            guard let self = self else { return }
            
            for request in requests {
                guard case .toDevice = request else {
                    continue
                }
                
                group.addTask {
                    try await self.handleRequest(request)
                }
            }
        }
    }
    
    private func processOutgoingRequests() async throws {
        let requests = try machine.outgoingRequests()
        await withThrowingTaskGroup(of: Void.self) { [weak self] group in
            guard let self = self else { return }
            
            for request in requests {
                group.addTask {
                    try await self.handleRequest(request)
                }
            }
        }
    }
}

@available(iOS 13.0.0, *)
extension MXCryptoMachine: Logger {
    func log(logLine: String) {
        MXLog.debug("[MXCryptoMachine] \(logLine)")
    }
    
    func log(error: String) {
        MXLog.error("[MXCryptoMachine] \(error)")
    }
}

#endif
