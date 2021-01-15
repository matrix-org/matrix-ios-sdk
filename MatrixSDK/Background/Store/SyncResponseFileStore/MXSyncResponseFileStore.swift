// 
// Copyright 2020 The Matrix.org Foundation C.I.C
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

@objcMembers
/// Sync response storage in a file implementation.
public class MXSyncResponseFileStore: NSObject {
    
    private enum Constants {
        static let folderName = "SyncResponse"
        static let fileName = "syncResponse"
        static let fileEncoding: String.Encoding = .utf8
    }
    
    private let fileOperationQueue: DispatchQueue
    private var filePath: URL!
    private var credentials: MXCredentials!
    
    public override init() {
        fileOperationQueue = DispatchQueue(label: "MXSyncResponseFileStore-" + MXTools.generateSecret())
    }
    
    private func setupFilePath() {
        guard let userId = credentials.userId else {
            fatalError("Credentials must provide a user identifier")
        }
        var cachePath: URL!
        
        if let appGroupIdentifier = MXSDKOptions.sharedInstance().applicationGroupIdentifier {
            cachePath = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        } else {
            cachePath = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        }
        
        filePath = cachePath
            .appendingPathComponent(Constants.folderName)
            .appendingPathComponent(userId)
            .appendingPathComponent(Constants.fileName)
        
        fileOperationQueue.async {
            try? FileManager.default.createDirectory(at: self.filePath.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true,
                                                     attributes: nil)
        }
    }
    
    private func readData() -> MXSyncResponseStoreModel? {
        guard let filePath = filePath else {
            return nil
        }
        
        let stopwatch = MXStopwatch()
        
        var fileContents: String?
        
        fileOperationQueue.sync {
            fileContents = try? String(contentsOf: filePath,
                                       encoding: Constants.fileEncoding)
            NSLog("[MXSyncResponseFileStore] readData: File read lasted \(stopwatch.readable())")
        }
        guard let jsonString = fileContents else {
            return nil
        }
        guard let json = MXTools.deserialiseJSONString(jsonString) as? [AnyHashable: Any] else {
            return nil
        }
        return MXSyncResponseStoreModel(fromJSON: json)
    }
    
    private func saveData(_ data: MXSyncResponseStoreModel?) {
        guard let filePath = filePath else {
            return
        }
        
        let stopwatch = MXStopwatch()
        
        guard let data = data else {
            try? FileManager.default.removeItem(at: filePath)
            NSLog("[MXSyncResponseFileStore] saveData: File remove lasted \(stopwatch.readable())")
            return
        }
        fileOperationQueue.async {
            try? data.jsonString()?.write(to: self.filePath,
                                          atomically: true,
                                          encoding: Constants.fileEncoding)
            NSLog("[MXSyncResponseFileStore] saveData: File write lasted \(stopwatch.readable())")
        }
    }
    
}

//  MARK: - MXSyncResponseStore

extension MXSyncResponseFileStore: MXSyncResponseStore {
    
    public func open(withCredentials credentials: MXCredentials) {
        self.credentials = credentials
        self.setupFilePath()
    }
    
    public var prevBatch: String? {
        get {
            return readData()?.prevBatch
        } set {
            let data = readData() ?? MXSyncResponseStoreModel()
            data.prevBatch = newValue
            saveData(data)
        }
    }
    
    public var syncResponse: MXSyncResponse? {
        get {
            return readData()?.syncResponse
        } set {
            let data = readData() ?? MXSyncResponseStoreModel()
            data.syncResponse = newValue
            saveData(data)
        }
    }
    
    public func event(withEventId eventId: String, inRoom roomId: String) -> MXEvent? {
        guard let response = syncResponse else {
            return nil
        }
        
        var allEvents: [MXEvent] = []
        if let joinedRoomSync = response.rooms.join[roomId] {
            allEvents.appendIfNotNil(contentsOf: joinedRoomSync.state?.events)
            allEvents.appendIfNotNil(contentsOf: joinedRoomSync.timeline?.events)
            allEvents.appendIfNotNil(contentsOf: joinedRoomSync.accountData?.events)
        }
        if let invitedRoomSync = response.rooms.invite[roomId] {
            allEvents.appendIfNotNil(contentsOf: invitedRoomSync.inviteState?.events)
        }
        if let leftRoomSync = response.rooms.leave[roomId] {
            allEvents.appendIfNotNil(contentsOf: leftRoomSync.state?.events)
            allEvents.appendIfNotNil(contentsOf: leftRoomSync.timeline?.events)
            allEvents.appendIfNotNil(contentsOf: leftRoomSync.accountData?.events)
        }
        
        let result = allEvents.first(where: { eventId == $0.eventId })
        result?.roomId = roomId
        
        NSLog("[MXSyncResponseFileStore] eventWithEventId: \(eventId) \(result == nil ? "not " : "" )found")
        
        return result
    }
    
    public func roomSummary(forRoomId roomId: String, using summary: MXRoomSummary?) -> MXRoomSummary? {
        guard let response = syncResponse else {
            return summary
        }
        guard let summary = summary ?? MXRoomSummary(roomId: roomId, andMatrixSession: nil) else {
            return nil
        }
        
        var eventsToProcess: [MXEvent] = []
        
        if let invitedRoomSync = response.rooms.invite[roomId],
            let stateEvents = invitedRoomSync.inviteState?.events {
            eventsToProcess.append(contentsOf: stateEvents)
        }
        
        if let joinedRoomSync = response.rooms.join[roomId] {
            if let stateEvents = joinedRoomSync.state?.events {
                eventsToProcess.append(contentsOf: stateEvents)
            }
            if let timelineEvents = joinedRoomSync.timeline?.events {
                eventsToProcess.append(contentsOf: timelineEvents)
            }
        }
        
        if let leftRoomSync = response.rooms.leave[roomId] {
            if let stateEvents = leftRoomSync.state?.events {
                eventsToProcess.append(contentsOf: stateEvents)
            }
            if let timelineEvents = leftRoomSync.timeline?.events {
                eventsToProcess.append(contentsOf: timelineEvents)
            }
        }
        
        for event in eventsToProcess {
            switch event.eventType {
            case .roomAliases:
                if summary.displayname == nil {
                    summary.displayname = (event.content["aliases"] as? [String])?.first
                }
            case .roomCanonicalAlias:
                if summary.displayname == nil {
                    summary.displayname = event.content["alias"] as? String
                    if summary.displayname == nil {
                        summary.displayname = (event.content["alt_aliases"] as? [String])?.first
                    }
                }
            case .roomName:
                summary.displayname = event.content["name"] as? String
            default:
                break
            }
        }
        return summary
    }
    
    public func deleteData() {
        saveData(nil)
    }
    
}

//  MARK: - Private

private extension Array {
    
    mutating func appendIfNotNil(contentsOf array: Array?) {
        if let array = array {
            append(contentsOf: array)
        }
    }
    
}
