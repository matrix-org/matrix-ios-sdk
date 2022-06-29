//
//  MXCryptoRequests.swift
//  MatrixSDK
//
//  Created by Element on 27/06/2022.
//

import Foundation

#if DEBUG

/// Convenience class to delegate network requests originating in Rust crypto module
/// to the native REST API client
@available(iOS 13.0.0, macOS 10.15.0, *)
struct MXCryptoRequests {
    private let restClient: MXRestClient
    init(restClient: MXRestClient) {
        self.restClient = restClient
    }
    
    func sendToDevice(request: ToDeviceRequest) async throws {
        return try await performCallbackRequest {
            restClient.sendDirectToDevice(
                eventType: request.eventType,
                contentMap: request.contentMap,
                txnId: nil,
                completion: $0
            )
        }
    }
    
    func uploadKeys(request: UploadKeysRequest) async throws -> MXKeysUploadResponse {
        return try await performCallbackRequest {
            restClient.uploadKeys(
                request.deviceKeys,
                oneTimeKeys: request.oneTimeKeys,
                fallbackKeys: nil,
                forDevice: request.deviceId,
                completion: $0
            )
        }
    }
    
    func queryKeys(users: [String]) async throws -> MXKeysQueryResponse {
        return try await performCallbackRequest {
            restClient.downloadKeys(forUsers: users, completion: $0)
        }
    }
    
    func claimKeys(request: ClaimKeysRequest) async throws -> MXKeysClaimResponse {
        return try await performCallbackRequest {
            restClient.claimOneTimeKeys(for: request.devices, completion: $0)
        }
    }
}

/// Convenience structs mapping Rust requests to data for native REST API requests
@available(iOS 13.0.0, macOS 10.15.0, *)
extension MXCryptoRequests {
    enum Error: Swift.Error {
        case cannotCreateRequest
    }
    
    struct ToDeviceRequest {
        let eventType: String
        let contentMap: MXUsersDevicesMap<NSDictionary>
        
        init(eventType: String, body: String) throws {
            guard
                let json = MXTools.deserialiseJSONString(body) as? [String: [String: NSDictionary]],
                let contentMap = MXUsersDevicesMap<NSDictionary>(map: json)
            else {
                throw Error.cannotCreateRequest
            }
            
            self.eventType = eventType
            self.contentMap = contentMap
        }
    }
    
    struct UploadKeysRequest {
        let deviceKeys: [String: Any]?
        let oneTimeKeys: [String: Any]?
        let deviceId: String
        
        init(body: String, deviceId: String) throws {
            guard let json = MXTools.deserialiseJSONString(body) as? [String: Any] else {
                throw Error.cannotCreateRequest
            }
            
            self.deviceKeys = json["device_keys"] as? [String : Any]
            self.oneTimeKeys = json["one_time_keys"] as? [String : Any]
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
}

#endif
