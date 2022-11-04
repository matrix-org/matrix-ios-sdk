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

/// Object responsible for decrypting room events and dealing with undecryptable events
protocol MXRoomEventDecrypting: Actor {
    
    /// Decrypt a list of events
    func decrypt(events: [MXEvent]) -> [MXEventDecryptionResult]
    
    /// Process an event that may contain room key and retry decryption if it does
    ///
    /// Note: room key could be contained in `m.room_key` or `m.forwarded_room_key`
    func handlePossibleRoomKeyEvent(_ event: MXEvent)
    
    /// Retry decrypting all previously undecrypted events
    ///
    /// Note: this may be useful if we have just imported keys from backup / file
    func retryAllUndecryptedEvents()
    
    /// Reset the store of undecrypted events
    func resetUndecryptedEvents()
}

/// Implementation of `MXRoomEventDecrypting` as an Actor
actor MXRoomEventDecryption: MXRoomEventDecrypting {
    typealias SessionId = String
    typealias EventId = String
        
    private let handler: MXCryptoRoomEventDecrypting
    private var undecryptedEvents: [SessionId: [EventId: MXEvent]]
    private let log = MXNamedLog(name: "MXCryptoRoomEventDecryptor")
    
    init(handler: MXCryptoRoomEventDecrypting) {
        self.handler = handler
        self.undecryptedEvents = [:]
    }
    
    func decrypt(events: [MXEvent]) -> [MXEventDecryptionResult] {
        let results = events.map(decrypt(event:))
        
        let undecrypted = results.filter {
            $0.clearEvent == nil || $0.error != nil
        }
        
        if !undecrypted.isEmpty {
            log.error("Unable to decrypt some event(s)", context: [
                "total": events.count,
                "undecrypted": undecrypted.count
            ])
        } else {
            log.debug("Decrypted all \(events.count) event(s)")
        }
        
        return results
    }
    
    func handlePossibleRoomKeyEvent(_ event: MXEvent) {
        guard let sessionId = roomKeySessionId(for: event) else {
            return
        }
        
        log.debug("Recieved a new room key as `\(event.type ?? "")` for session \(sessionId)")
        let events = undecryptedEvents[sessionId]?.map(\.value) ?? []
        retryDecryption(events: events)
    }
    
    func retryAllUndecryptedEvents() {
        let allEvents = undecryptedEvents
            .flatMap {
                $0.value.map {
                    $0.value
                }
            }
        retryDecryption(events: allEvents)
    }
    
    func resetUndecryptedEvents() {
        undecryptedEvents = [:]
    }
    
    // MARK: - Private
    
    private func decrypt(event: MXEvent) -> MXEventDecryptionResult {
        guard
            let sessionId = sessionId(for: event),
            event.content?["algorithm"] as? String == kMXCryptoMegolmAlgorithm
        else {
            log.debug("Ignoring unencrypted or non-room event")
            return MXEventDecryptionResult()
        }
        
        do {
            let decryptedEvent = try handler.decryptRoomEvent(event)
            let result = try MXEventDecryptionResult(event: decryptedEvent)
            log.debug("Successfully decrypted event `\(result.clearEvent["type"] ?? "unknown")`")
            return result
            
        // `Megolm` error does not currently expose the type of "missing keys" error, so have to match against
        // hardcoded non-localized error message. Will be changed in future PR
        } catch DecryptionError.Megolm(message: "decryption failed because the room key is missing") {
            if undecryptedEvents[sessionId] == nil {
                log.error("Failed to decrypt event due to missing room keys (further errors for the same key will be supressed)", context: [
                    "session_id": sessionId
                ])
            }
            
            addUndecryptedEvent(event)
            
            let result = MXEventDecryptionResult()
            result.error = NSError(
                domain: MXDecryptingErrorDomain,
                code: Int(MXDecryptingErrorUnknownInboundSessionIdCode.rawValue),
                userInfo: [
                    NSLocalizedDescriptionKey: MXDecryptingErrorUnknownInboundSessionIdReason
                ]
            )
            return result
        } catch {
            log.error("Failed to decrypt event", context: error)
            addUndecryptedEvent(event)
            
            let result = MXEventDecryptionResult()
            result.error = error
            return result
        }
    }
    
    private func addUndecryptedEvent(_ event: MXEvent) {
        guard let sessionId = sessionId(for: event) else {
            return
        }
        
        var events = undecryptedEvents[sessionId] ?? [:]
        events[event.eventId] = event
        undecryptedEvents[sessionId] = events
    }
    
    private func removeUndecryptedEvent(_ event: MXEvent) {
        guard let sessionId = sessionId(for: event) else {
            return
        }
        undecryptedEvents[sessionId]?[event.eventId] = nil
    }
    
    private func retryDecryption(events: [MXEvent]) {
        guard !events.isEmpty else {
            return
        }
        
        log.debug("Re-decrypting \(events.count) event(s)")
        
        var results = [(MXEvent, MXEventDecryptionResult)]()
        for event in events {
            guard event.clear == nil else {
                removeUndecryptedEvent(event)
                continue
            }
            
            let result = decrypt(event: event)
            guard result.clearEvent != nil else {
                log.error("Event still not decryptable", context: [
                    "event_id": event.eventId ?? "unknown",
                    "session_id": sessionId(for: event)
                ])
                continue
            }
            
            removeUndecryptedEvent(event)
            results.append((event, result))
        }
        
        Task { [results] in
            await MainActor.run {
                for (event, result) in results {
                    event.setClearData(result)
                }
            }
        }
    }
    
    private func roomKeySessionId(for event: MXEvent) -> String? {
        if event.eventType == .roomKey, let content = MXRoomKeyEventContent(fromJSON: event.content) {
            return content.sessionId
        } else if event.eventType == .roomForwardedKey, let content = MXForwardedRoomKeyEventContent(fromJSON: event.content) {
            return content.sessionId
        } else {
            return nil
        }
    }
    
    private func sessionId(for event: MXEvent) -> String? {
        guard event.isEncrypted, let sessionId = event.content["session_id"] as? String else {
            log.error("Event is not encrypted or is missing session id")
            return nil
        }
        return sessionId
    }
}

#endif
