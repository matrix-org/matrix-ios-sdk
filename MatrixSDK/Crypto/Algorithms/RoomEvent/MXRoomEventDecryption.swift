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

/// Object responsible for decrypting room events and dealing with undecryptable events
protocol MXRoomEventDecrypting: Actor {
    
    /// Decrypt a list of events
    func decrypt(events: [MXEvent]) -> [MXEventDecryptionResult]
    
    /// Process an event that may contain room key and retry decryption if it does
    ///
    /// Note: room key could be contained in `m.room_key` or `m.forwarded_room_key`
    func handlePossibleRoomKeyEvent(_ event: MXEvent)
    
    /// Retry decrypting events with specific session ids
    ///
    /// Note: this may be useful if we have just imported keys from backup / file
    func retryUndecryptedEvents(sessionIds: [String])
    
    /// Reset the store of undecrypted events
    func resetUndecryptedEvents()
}

/// Implementation of `MXRoomEventDecrypting` as an Actor
actor MXRoomEventDecryption: MXRoomEventDecrypting {
    typealias SessionId = String
    typealias EventId = String
        
    private let handler: MXCryptoRoomEventDecrypting
    private var undecryptedEvents: [SessionId: [EventId: MXEvent]]
    private let log = MXNamedLog(name: "MXRoomEventDecryption")
    
    init(handler: MXCryptoRoomEventDecrypting) {
        self.handler = handler
        self.undecryptedEvents = [:]
    }
    
    func decrypt(events: [MXEvent]) -> [MXEventDecryptionResult] {
        log.debug("Decrypting \(events.count) event(s)")
        let results = events.map(decrypt(event:))
        
        let undecrypted = results.filter {
            $0.clearEvent == nil || $0.error != nil
        }
        
        if !undecrypted.isEmpty {
            log.warning("Unable to decrypt \(undecrypted.count) out of \(events.count) event(s)")
        } else if events.count > 1 {
            log.debug("Decrypted all \(events.count) events")
        }
        
        return results
    }
    
    func handlePossibleRoomKeyEvent(_ event: MXEvent) {
        guard let sessionId = roomKeySessionId(for: event) else {
            return
        }
        
        log.debug("Received a new room key as `\(event.type ?? "")` for session \(sessionId)")
        let events = undecryptedEvents[sessionId]?.map(\.value) ?? []
        retryDecryption(events: events)
    }
    
    func retryUndecryptedEvents(sessionIds: [String]) {
        let events = sessionIds
            .flatMap {
                undecryptedEvents[$0]?.map {
                    $0.value
                } ?? []
            }
        retryDecryption(events: events)
    }
    
    func resetUndecryptedEvents() {
        undecryptedEvents = [:]
    }
    
    // MARK: - Private
    
    private func decrypt(event: MXEvent) -> MXEventDecryptionResult {
        let eventId = event.eventId ?? "unknown"
        
        guard
            event.isEncrypted && event.clear == nil,
            event.content?["algorithm"] as? String == kMXCryptoMegolmAlgorithm,
            let sessionId = sessionId(for: event)
        else {
            if !event.isEncrypted {
                log.debug("Ignoring unencrypted event`\(eventId)`")
            } else if event.clear != nil {
                log.debug("Ignoring already decrypted event`\(eventId)`")
            } else {
                log.debug("Ignoring non-room event `\(eventId)`")
            }
            
            return event.decryptionResult
        }
        
        do {
            let decryptedEvent = try handler.decryptRoomEvent(event)
            let result = try MXEventDecryptionResult(event: decryptedEvent)
            log.debug("Decrypted event `\(result.clearEvent["type"] ?? "unknown")` eventId `\(eventId)`")
            return result
            
        } catch let error as DecryptionError {
            return handleDecryptionError(for: event, sessionId: sessionId, error: error)
        } catch {
            return handleGenericError(for: event, sessionId: sessionId, error: error)
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
                    "session_id": sessionId(for: event),
                    "error": result.error.localizedDescription
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
        let sessionId = event.content["session_id"] ?? event.wireContent["session_id"]
        guard let sessionId = sessionId as? String else {
            log.failure("Event is missing session id")
            return nil
        }
        return sessionId
    }

    // MARK: - Error handling

    private func handleDecryptionError(for event: MXEvent, sessionId: String, error: DecryptionError) -> MXEventDecryptionResult {
        switch error {
        case .Identifier(let message):
            log.error("Failed to decrypt event due to identifier", context: [
                "session_id": sessionId,
                "message": message,
                "error": error
            ])
            return trackedDecryptionResult(for: event, error: error)
            
        case .Serialization(let message):
            log.error("Failed to decrypt event due to serialization", context: [
                "session_id": sessionId,
                "message": message,
                "error": error
            ])
            return trackedDecryptionResult(for: event, error: error)
            
        case .Megolm(let message):
            log.error("Failed to decrypt event due to megolm error", context: [
                "session_id": sessionId,
                "message": message,
                "error": error
            ])
            return trackedDecryptionResult(for: event, error: error)
            
        case .MissingRoomKey(let message, let withheldCode):
            if undecryptedEvents[sessionId] == nil {
                log.error("Failed to decrypt event(s) due to missing room keys", context: [
                    "session_id": sessionId,
                    "message": message,
                    "error": error,
                    "withheldCode": withheldCode ?? "N/A",
                    "details": "further errors for the same key will be supressed",
                ])
            }
            
            let keysError = NSError(
                domain: MXDecryptingErrorDomain,
                code: Int(MXDecryptingErrorUnknownInboundSessionIdCode.rawValue),
                userInfo: [
                    NSLocalizedDescriptionKey: MXDecryptingErrorUnknownInboundSessionIdReason
                ]
            )
            return trackedDecryptionResult(for: event, error: keysError)
            
        case .Store(let message):
            log.error("Failed to decrypt event due to store error", context: [
                "session_id": sessionId,
                "message": message,
                "error": error
            ])
            return trackedDecryptionResult(for: event, error: error)
        }
    }
    
    private func handleGenericError(for event: MXEvent, sessionId: String, error: Error) -> MXEventDecryptionResult {
        log.error("Failed to decrypt event", context: [
            "session_id": sessionId,
            "error": error
        ])
        return trackedDecryptionResult(for: event, error: error)
    }
    
    private func trackedDecryptionResult(for event: MXEvent, error: Error) -> MXEventDecryptionResult {
        log.debug("Unable to decrypt event `\(event.eventId ?? "unknown")`")
        addUndecryptedEvent(event)
        
        let result = MXEventDecryptionResult()
        result.error = error
        return result
    }
}

