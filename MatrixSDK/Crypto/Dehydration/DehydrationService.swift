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
import MatrixSDKCrypto

enum DehydrationServiceError: Error {
    case failedDehydration(Error)
    case noDehydratedDeviceAvailable(Error)
    case failedRehydration(Error)
    case invalidRehydratedDeviceData
    case failedStoringSecret(Error)
    case failedRetrievingSecret(Error)
    case failedRetrievingPrivateKey(Error)
    case invalidSecretStorageDefaultKeyId
    case failedRetrievingToDeviceEvents(Error)
    case failedDeletingDehydratedDevice(Error)
}

@objcMembers
public class DehydrationService: NSObject {
    let deviceDisplayName = "Backup Device"
    let restClient: MXRestClient
    let secretStorage: MXSecretStorage
    let dehydratedDevices: DehydratedDevicesProtocol
    
    
    init(restClient: MXRestClient, secretStorage: MXSecretStorage, dehydratedDevices: DehydratedDevicesProtocol) {
        self.restClient = restClient
        self.secretStorage = secretStorage
        self.dehydratedDevices = dehydratedDevices
    }
    
    public func runDeviceDehydrationFlow(privateKeyData: Data) async {
        do {
            try await _runDeviceDehydrationFlow(privateKeyData: privateKeyData)
        } catch {
            MXLog.error("Failed device dehydration flow", context: error)
        }
    }
    
    private func _runDeviceDehydrationFlow(privateKeyData: Data) async throws {
        guard let secretStorageKeyId = self.secretStorage.defaultKeyId() else {
            throw DehydrationServiceError.invalidSecretStorageDefaultKeyId
        }
        
        let secretId = MXSecretId.dehydratedDevice.takeUnretainedValue() as String
        
        // If we have a dehydration pickle key stored on the backend, use it to rehydrate a device, then process
        // that device's events and then create a new dehydrated device
        if secretStorage.hasSecret(withSecretId: secretId, withSecretStorageKeyId: secretStorageKeyId) {
            // If available, retrieve the base64 encoded pickle key from the backend
            let base64PickleKey = try await retrieveSecret(forSecretId: secretId, secretStorageKey: secretStorageKeyId, privateKeyData: privateKeyData)

            // Convert it back to Data
            let pickleKeyData = MXBase64Tools.data(fromBase64: base64PickleKey)
            
            let rehydrationResult = await rehydrateDevice(pickleKeyData: pickleKeyData)
            switch rehydrationResult {
            case .success((let deviceId, let rehydratedDevice)):
                // Fetch and process the to device events available on the dehydrated device
                try await processToDeviceEvents(rehydratedDevice: rehydratedDevice, deviceId: deviceId)
                
                // And attempt to delete the dehydrated device but ignore failures
                try? await deleteDehydratedDevice(deviceId: deviceId)
            case .failure(let error):
                // If no dehydrated devices are available just continue and create a new one
                if case .noDehydratedDeviceAvailable = error {
                    break
                } else {
                    throw error
                }
            }
            
            // Finally, create a new dehydrated device with the same pickle key
            try await dehydrateDevice(pickleKeyData: pickleKeyData)
        } else { // Otherwise, generate a new dehydration pickle key, store it and dehydrate a device
            // Generate a new dehydration pickle key
            var pickleKeyRaw = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, 32, &pickleKeyRaw)
            let pickleKeyData = Data(bytes: pickleKeyRaw, count: 32)
            
            // Convert it to unpadded base 64
            let base64PickleKey = MXBase64Tools.unpaddedBase64(from: pickleKeyData)
            
            // Store it on the backend
            try await storeSecret(base64PickleKey, secretId: secretId, secretStorageKeys: [secretStorageKeyId: privateKeyData])
            
            // Dehydrate a new device using the new pickle key
            try await dehydrateDevice(pickleKeyData: pickleKeyData)
        }
    }
    
    // MARK: - Secret storage
    
    private func storeSecret(_ unpaddedBase64Secret: String, secretId: String, secretStorageKeys: [String: Data]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.secretStorage.storeSecret(unpaddedBase64Secret, withSecretId: secretId, withSecretStorageKeys: secretStorageKeys) { secretId in
                MXLog.info("Stored secret with secret id: \(secretId)")
                continuation.resume()
            } failure: { error in
                MXLog.error("Failed storing secret", context: error)
                continuation.resume(throwing: DehydrationServiceError.failedStoringSecret(error))
            }
        }
    }
    
    private func retrieveSecret(forSecretId secretId: String, secretStorageKey: String, privateKeyData: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.secretStorage.secret(withSecretId: secretId, withSecretStorageKeyId: secretStorageKey, privateKey: privateKeyData) { secret in
                MXLog.info("Retrieved secret with secret id: \(secretId)")
                continuation.resume(returning: secret)
            } failure: { error in
                MXLog.error("Failed retrieving secret", context: error)
                continuation.resume(throwing: DehydrationServiceError.failedRetrievingSecret(error))
            }
        }
    }
    
    // MARK: - Device dehydration
    
    private func dehydrateDevice(pickleKeyData: Data) async throws {
        let dehydratedDevice = try dehydratedDevices.create()

        let requestDetails = try dehydratedDevice.keysForUpload(deviceDisplayName: deviceDisplayName, pickleKey: pickleKeyData)
        
        let parameters = MXDehydratedDeviceCreationParameters()
        parameters.body = requestDetails.body

        return try await withCheckedThrowingContinuation { continuation in
            restClient.createDehydratedDevice(parameters) { deviceId in
                MXLog.info("Successfully created dehydrated device with id: \(deviceId)")
                continuation.resume()
            } failure: { error in
                MXLog.error("Failed creating dehydrated device", context: error)
                continuation.resume(throwing: DehydrationServiceError.failedDehydration(error))
            }
        }
    }
    
    private func rehydrateDevice(pickleKeyData: Data) async -> Result<(deviceId: String, rehydratedDevice: RehydratedDeviceProtocol), DehydrationServiceError>  {
        await withCheckedContinuation { continuation in
            self.restClient.retrieveDehydratedDevice { [weak self] dehydratedDevice in
                guard let self else { return }
                
                MXLog.info("Successfully retrieved dehydrated device with id: \(dehydratedDevice.deviceId)")
                                
                guard let deviceDataJSON = MXTools.serialiseJSONObject(dehydratedDevice.deviceData) else {
                    continuation.resume(returning: .failure(DehydrationServiceError.invalidRehydratedDeviceData))
                    return
                }
                
                do {
                    let rehydratedDevice = try self.dehydratedDevices.rehydrate(pickleKey: pickleKeyData, deviceId: dehydratedDevice.deviceId, deviceData: deviceDataJSON)
                    continuation.resume(returning: .success((dehydratedDevice.deviceId, rehydratedDevice)))
                } catch {
                    continuation.resume(returning: .failure(DehydrationServiceError.failedRehydration(error)))
                }
            } failure: { error in
                MXLog.error("Failed retrieving dehidrated device", context: error)
                if let mxError = MXError(nsError: error),
                   mxError.errcode == kMXErrCodeStringNotFound {
                    continuation.resume(returning: .failure(DehydrationServiceError.noDehydratedDeviceAvailable(error)))
                } else {
                    continuation.resume(returning: .failure(DehydrationServiceError.failedRehydration(error)))
                }
            }
        }
    }
    
    private func deleteDehydratedDevice(deviceId: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            restClient.deleteDehydratedDevice {
                MXLog.info("Deleted dehydrated device with id: \(deviceId)")
                continuation.resume()
            } failure: { error in
                MXLog.error("Failed retrieving dehydrated device events", context: error)
                continuation.resume(throwing: DehydrationServiceError.failedRetrievingPrivateKey(error))
            }
        }
    }
    
    // MARK: - To device event processing
    
    private func processToDeviceEvents(rehydratedDevice: RehydratedDeviceProtocol, deviceId: String) async throws {
        var dehydratedDeviceEventsResponse: MXDehydratedDeviceEventsResponse?
        
        repeat {
            let response = try await retrieveToDeviceEvents(deviceId: deviceId, nextBatch: dehydratedDeviceEventsResponse?.nextBatch)
            try rehydratedDevice.receiveEvents(events: MXTools.serialiseJSONObject(response.events))
            dehydratedDeviceEventsResponse = response
            
        } while !(dehydratedDeviceEventsResponse?.events.isEmpty ?? true)
    }
    
    private func retrieveToDeviceEvents(deviceId: String, nextBatch: String?) async throws -> MXDehydratedDeviceEventsResponse {
        try await withCheckedThrowingContinuation { continuation in
            restClient.retrieveDehydratedDeviceEvents(forDeviceId: deviceId, nextBatch: nextBatch) { dehydratedDeviceEventsResponse in
                MXLog.info("Retrieved dehydrated device events for device id: \(deviceId)")
                continuation.resume(returning: dehydratedDeviceEventsResponse)
            } failure: { error in
                MXLog.error("Failed deleting dehydrated device", context: error)
                continuation.resume(throwing: DehydrationServiceError.failedDeletingDehydratedDevice(error))
            }
        }
    }
}
