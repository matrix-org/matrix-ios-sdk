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

/// MXBeaconAggregations aggregates related beacon info events and beacon info events into a summary object MXBeaconInfoSummary
@objcMembers
public class MXBeaconAggregations: NSObject {
    
    // MARK: - Properties
    
    private unowned let session: MXSession
    
    private var perRoomListeners: [MXBeaconInfoSummaryPerRoomListener] = []
    private var perRoomDeletionListeners: [MXBeaconInfoSummaryDeletionPerRoomListener] = []
    
    private var allRoomListeners: [MXBeaconInfoSummaryAllRoomListener] = []
    private var allRoomDeletionListeners: [MXBeaconInfoSummaryDeletionAllRoomListener] = []
    
    private var beaconInfoSummaryStore: MXBeaconInfoSummaryStoreProtocol
    
    // MARK: - Setup
    
    public init(session: MXSession, store: MXBeaconInfoSummaryStoreProtocol) {
        self.session = session
        self.beaconInfoSummaryStore = store
        
        super.init()
    }
    
    // MARK: - Public
    
    /// Get MXBeaconInfoSummary from the first beacon info event id
    public func beaconInfoSummary(for eventId: String, inRoomWithId roomId: String) -> MXBeaconInfoSummaryProtocol? {
        return self.beaconInfoSummaryStore.getBeaconInfoSummary(withIdentifier: eventId, inRoomWithId: roomId)
    }
    
    /// Get all MXBeaconInfoSummary in a room
    public func getBeaconInfoSummaries(inRoomWithId roomId: String) -> [MXBeaconInfoSummaryProtocol] {
        return self.beaconInfoSummaryStore.getAllBeaconInfoSummaries(inRoomWithId: roomId)
    }
    
    /// Get all MXBeaconInfoSummary in a room for a user
    public func getBeaconInfoSummaries(for userId: String, inRoomWithId roomId: String) -> [MXBeaconInfoSummaryProtocol] {
        return self.beaconInfoSummaryStore.getBeaconInfoSummaries(for: userId, inRoomWithId: roomId)
    }
    
    /// Get all MXBeaconInfoSummary for a user
    public func getBeaconInfoSummaries(for userId: String) -> [MXBeaconInfoSummaryProtocol] {
        return self.beaconInfoSummaryStore.getAllBeaconInfoSummaries(forUserId: userId)
    }
    
    /// Update a MXBeaconInfoSummary device id that belongs to the current user.
    /// Enables to recognize that a beacon info has been started on the device
    public func updateBeaconInfoSummary(with eventId: String, deviceId: String, inRoomWithId roomId: String)  {
        guard let beaconInfoSummary = self.beaconInfoSummaryStore.getBeaconInfoSummary(withIdentifier: eventId, inRoomWithId: roomId) else {
            return
        }
        
        guard beaconInfoSummary.userId == session.myUserId else {
            return
        }
        
        if beaconInfoSummary.updateWithDeviceId(deviceId) {
            self.beaconInfoSummaryStore.addOrUpdateBeaconInfoSummary(beaconInfoSummary, inRoomWithId: roomId)
            self.notifyBeaconInfoSummaryListeners(ofRoomWithId: roomId, beaconInfoSummary: beaconInfoSummary)
        }
    }
    
    public func clearData(inRoomWithId roomId: String) {
        // TODO: Notify data clear
        self.beaconInfoSummaryStore.deleteAllBeaconInfoSummaries(inRoomWithId: roomId)
    }
    
    // MARK: Data update
    
    public func handleBeacon(event: MXEvent) {
        guard let roomId = event.roomId else {
            return
        }
        
        guard event.isRedactedEvent() == false else {
            return
        }
        
        guard let beacon = MXBeacon(mxEvent: event) else {
            return
        }
                
        guard let beaconInfoSummary = self.getBeaconInfoSummary(withIdentifier: beacon.beaconInfoEventId, inRoomWithId: roomId), self.canAddBeacon(beacon, to: beaconInfoSummary) else {
            return
        }
        
        if beaconInfoSummary.updateWithLastBeacon(beacon) {
            self.beaconInfoSummaryStore.addOrUpdateBeaconInfoSummary(beaconInfoSummary, inRoomWithId: roomId)
            self.notifyBeaconInfoSummaryListeners(ofRoomWithId: roomId, beaconInfoSummary: beaconInfoSummary)
        }
    }
    
    public func handleBeaconInfo(event: MXEvent) {
        guard let roomId = event.roomId else {
            return
        }
        
        if event.isRedactedEvent() {
            self.handleRedactedBeaconInfo(with: event, roomId: roomId)
            return
        }
        
        guard let beaconInfo = MXBeaconInfo(mxEvent: event) else {
            return
        }
        
        self.addOrUpdateBeaconInfo(beaconInfo, inRoomWithId: roomId)
    }
    
    private func handleRedactedBeaconInfo(with event: MXEvent, roomId: String) {
        
        guard let beaconInfoEventId = event.eventId else {
            return
        }
        
        // If `m.beacon_info` event is redacted remove the associated MXbeaconInfoSummary if exists.
        if let beaconInfoSummary = self.beaconInfoSummaryStore.getBeaconInfoSummary(withIdentifier: beaconInfoEventId, inRoomWithId: roomId) {
            
            // Delete beacon info summary
            self.beaconInfoSummaryStore.deleteBeaconInfoSummary(with: beaconInfoEventId, inRoomWithId: roomId)
            
            // If the beacon info belongs to the current user
            if beaconInfoSummary.userId == session.myUserId {
                
                // Redact associated stopped beacon info if exists
                self.redactStoppedBeaconInfoAssociatedToBeaconInfo(eventId: beaconInfoEventId, inRoomWithId: roomId)
                
                // Redact associated beacon events
                self.redactBeaconsRelatedToBeaconInfo(with: beaconInfoEventId, inRoomWithId: beaconInfoSummary.roomId)
                
            }
            
            self.notifyBeaconInfoSummaryDeletionListeners(ofRoomWithId: roomId, beaconInfoEventId: beaconInfoEventId)
        }
    }
    
    private func redactBeaconsRelatedToBeaconInfo(with eventId: String, inRoomWithId roomId: String) {
        guard let room = self.session.room(withRoomId: roomId) else {
            return
        }
        
        let relationEvents = self.session.store.relations(forEvent: eventId, inRoom: roomId, relationType: MXEventRelationTypeReference)
        
        for relationEvent in relationEvents where relationEvent.eventType == .beacon && relationEvent.isRedactedEvent() == false {
            
            room.redactEvent(relationEvent.eventId, reason: nil) { response in
                if case .failure(let error) = response {
                    MXLog.error("[MXBeaconAggregations] Failed to redact m.beacon event", context: error)
                }
            }
        }
    }
    
    private func redactStoppedBeaconInfoAssociatedToBeaconInfo(eventId beaconInfoEnventId: String, inRoomWithId roomId: String) {
        guard let room = self.session.room(withRoomId: roomId) else {
            return
        }
        
        self.session.locationService.getStoppedBeaconInfo(for: beaconInfoEnventId, inRoomWithId: roomId) { stoppedBeaconInfo in
         
            if let eventId = stoppedBeaconInfo?.originalEvent?.eventId {
                // Redact stopped beacon info
                room.redactEvent(eventId, reason: nil) { response in
                    if case .failure(let error) = response {
                        MXLog.error("[MXBeaconAggregations] Failed to redact stopped m.beacon_info event", context: error)
                    }
                }
            }
        }
    }
    
    // MARK: Data update listener
    
    /// Listen to all beacon info summary updates in a room
    public func listenToBeaconInfoSummaryUpdateInRoom(withId roomId: String, handler: @escaping (MXBeaconInfoSummaryProtocol) -> Void) -> AnyObject? {
        let listener = MXBeaconInfoSummaryPerRoomListener(roomId: roomId, notificationHandler: handler)
        
        perRoomListeners.append(listener)

        return listener
    }
    
    /// Listen to all beacon info summary update in all rooms
    public func listenToBeaconInfoSummaryUpdate(handler: @escaping (_ roomId: String, MXBeaconInfoSummaryProtocol) -> Void) -> AnyObject? {
        let listener = MXBeaconInfoSummaryAllRoomListener(notificationHandler: handler)
        
        allRoomListeners.append(listener)

        return listener
    }
    
    /// Listen to all beacon info summary deletion in a room
    public func listenToBeaconInfoSummaryDeletionInRoom(withId roomId: String, handler: @escaping (_ beaconInfoEventId: String) -> Void) -> AnyObject? {
        let listener = MXBeaconInfoSummaryDeletionPerRoomListener(roomId: roomId, notificationHandler: handler)

        perRoomDeletionListeners.append(listener)

        return listener
    }
    
    /// Listen to all beacon info summary deletion in all rooms
    public func listenToBeaconInfoSummaryDeletion(handler: @escaping (_ roomId: String, _ beaconInfoEventId: String) -> Void) -> AnyObject? {
        let listener = MXBeaconInfoSummaryDeletionAllRoomListener(notificationHandler: handler)
        
        allRoomDeletionListeners.append(listener)

        return listener
    }

    public func removeListener(_ listener: Any) {
        if let perRoomListener = listener as? MXBeaconInfoSummaryPerRoomListener {
            perRoomListeners.removeAll(where: { $0 === perRoomListener })
        } else if let allRoomListener = listener as? MXBeaconInfoSummaryAllRoomListener {
            allRoomListeners.removeAll(where: { $0 === allRoomListener })
        } else if let perRoomDeletionListener = listener as? MXBeaconInfoSummaryDeletionPerRoomListener {
            perRoomDeletionListeners.removeAll(where: { $0 === perRoomDeletionListener })
        } else if let allRoomDeletionListener = listener as? MXBeaconInfoSummaryDeletionAllRoomListener {
            allRoomDeletionListeners.removeAll(where: { $0 === allRoomDeletionListener })
        }
    }
    
    // MARK: - Private
    
    private func addOrUpdateBeaconInfo(_ beaconInfo: MXBeaconInfo, inRoomWithId roomId: String) {
        
        guard let eventId = beaconInfo.originalEvent?.eventId else {
            return
        }
        
        var beaconInfoSummary: MXBeaconInfoSummary?
        
        // A new beacon info is emitted to set a current one to stop state.        
        if beaconInfo.isLive == false {
            
            // If no corresponding BeaconInfoSummary exists, discard this beacon info
            if let existingBeaconInfoSummary = self.getBeaconInfoSummary(withStoppedBeaconInfo: beaconInfo, inRoomWithId: roomId), existingBeaconInfoSummary.hasStopped == false {
                
                existingBeaconInfoSummary.updateWithBeaconInfo(beaconInfo)
                beaconInfoSummary = existingBeaconInfoSummary
            } else {
                MXLog.error("[MXBeaconAggregations] Fails to find beacon info summary associated to stopped beacon info", context: [
                    "event_id": eventId
                ])
            }
            
        } else if let existingBeaconInfoSummary = self.getBeaconInfoSummary(withIdentifier: eventId, inRoomWithId: roomId) {
            // Check if a beacon info summary exist with the same beacon info event id
            // If beacon info is older than existing one, do not take it into account
            if beaconInfo.timestamp > existingBeaconInfoSummary.beaconInfo.timestamp {
                existingBeaconInfoSummary.updateWithBeaconInfo(beaconInfo)
                beaconInfoSummary = existingBeaconInfoSummary
            }
        } else {
            
            var shouldStopNewBeaconInfo = false
            
            if let userId = beaconInfo.userId {
                
                // Retrieve existing live beacon info summaries for the user
                let existingLiveBeaconInfoSummaries = self.beaconInfoSummaryStore.getBeaconInfoSummaries(for: userId, inRoomWithId: roomId).sorted { firstSummary, secondSummary in
                    firstSummary.beaconInfo.timestamp < secondSummary.beaconInfo.timestamp
                }
                
                let beaconInfoSummariesToStop: [MXBeaconInfoSummary]
                
                let lastBeaconInfoSummary = existingLiveBeaconInfoSummaries.last
                
                if let lastBeaconInfoSummary = lastBeaconInfoSummary, beaconInfo.timestamp < lastBeaconInfoSummary.beaconInfo.timestamp {
                        // The received live beacon info is older than last existing one mark it as stopped
                        shouldStopNewBeaconInfo = true
                        
                        // Do not stop the last live beacon info
                        beaconInfoSummariesToStop = existingLiveBeaconInfoSummaries.filter({ summary in
                            summary.id != lastBeaconInfoSummary.id
                        })
                } else {
                    // Received beacon info is newer than existing one, stop other beacon info
                    beaconInfoSummariesToStop = existingLiveBeaconInfoSummaries
                }
                
                // Stop other existing live beacon info summaries
                for beaconInfoSummary in beaconInfoSummariesToStop {
                    let stoppedBeaconInfo = beaconInfoSummary.beaconInfo.stopped()
                    beaconInfoSummary.updateWithBeaconInfo(stoppedBeaconInfo)
                    self.beaconInfoSummaryStore.addOrUpdateBeaconInfoSummary(beaconInfoSummary, inRoomWithId: roomId)
                    self.notifyBeaconInfoSummaryListeners(ofRoomWithId: roomId, beaconInfoSummary: beaconInfoSummary)
                }
            }
            
            let finalBeaconInfo: MXBeaconInfo
            
            // We can only have one **live** beacon info per user and per room
            // If the received live beacon info is older than other existing live, mark it as stopped
            if shouldStopNewBeaconInfo {
                finalBeaconInfo = beaconInfo.stopped()
            } else {
                finalBeaconInfo = beaconInfo
            }
            
            beaconInfoSummary = MXBeaconInfoSummary(beaconInfo: finalBeaconInfo)
        }
        
        if let beaconInfoSummary = beaconInfoSummary {
            self.beaconInfoSummaryStore.addOrUpdateBeaconInfoSummary(beaconInfoSummary, inRoomWithId: roomId)
            self.notifyBeaconInfoSummaryListeners(ofRoomWithId: roomId, beaconInfoSummary: beaconInfoSummary)
        }
    }
    
    private func canAddBeacon(_ beacon: MXBeacon, to beaconInfoSummary: MXBeaconInfoSummary) -> Bool {
    
        guard beaconInfoSummary.hasStopped == false, beaconInfoSummary.hasExpired == false,
        beacon.timestamp < beaconInfoSummary.expiryTimestamp else {
            return false
        }
        
        if let lastBeacon = beaconInfoSummary.lastBeacon, beacon.timestamp < lastBeacon.timestamp {
            return false
        }
        
        return true
    }
    
    private func notifyBeaconInfoSummaryListeners(ofRoomWithId roomId: String, beaconInfoSummary: MXBeaconInfoSummary) {
        
        for listener in perRoomListeners where listener.roomId == roomId {
            listener.notificationHandler(beaconInfoSummary)
        }
        
        for listener in allRoomListeners {
            listener.notificationHandler(roomId, beaconInfoSummary)
        }
    }
    
    private func notifyBeaconInfoSummaryDeletionListeners(ofRoomWithId roomId: String, beaconInfoEventId: String) {
        
        for listener in perRoomDeletionListeners where listener.roomId == roomId {
            listener.notificationHandler(beaconInfoEventId)
        }
        
        for listener in allRoomDeletionListeners {
            listener.notificationHandler(roomId, beaconInfoEventId)
        }
    }
    
    /// Get MXBeaconInfoSummary class instead of MXBeaconInfoSummaryProtocol to have access to internal methods
    private func getBeaconInfoSummary(withIdentifier identifier: String, inRoomWithId roomId: String) -> MXBeaconInfoSummary? {
        return self.beaconInfoSummaryStore.getBeaconInfoSummary(withIdentifier: identifier, inRoomWithId: roomId)
    }
    
    private func getLiveBeaconInfoSummaries(for userId: String, inRoomWithId roomId: String) -> [MXBeaconInfoSummary] {
        
        let beaconInfoSummaries = self.beaconInfoSummaryStore.getBeaconInfoSummaries(for: userId, inRoomWithId: roomId)
        return beaconInfoSummaries.filter { beaconInfoSummary in
            return beaconInfoSummary.beaconInfo.isLive
        }
    }
    
    private func getBeaconInfoSummary(withStoppedBeaconInfo beaconInfo: MXBeaconInfo, inRoomWithId roomId: String) -> MXBeaconInfoSummary? {
        
        guard beaconInfo.isLive == false else {
            return nil
        }
        
        guard let userId = beaconInfo.userId else {
            return nil
        }
        
        return self.beaconInfoSummaryStore.getBeaconInfoSummary(withUserId: userId, description: beaconInfo.desc, timeout: beaconInfo.timeout, timestamp: beaconInfo.timestamp, inRoomWithId: roomId)
    }
}
