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

@objcMembers public class MXEventStreamService: NSObject {
    
    var listeners = [MXLiveEventListener]()

    public func add(eventStreamListener: MXLiveEventListener) {
        listeners.append(eventStreamListener)
    }

    public func remove(eventStreamListener: MXLiveEventListener) {
        listeners.removeAll { $0 === eventStreamListener }
    }
    
    public func dispatchLiveEventReceived(event: MXEvent, roomId: String, initialSync: Bool) {
        guard !initialSync else { return }
        listeners.forEach { listener in
            listener.onLiveEvent(roomId: roomId, event: event)
        }
    }

    public func dispatchPaginatedEventReceived(event: MXEvent, roomId: String) {
        listeners.forEach { listener in
            listener.onPaginatedEvent(roomId: roomId, event: event)
        }
    }

    public func dispatchLiveEventDecrypted(event: MXEvent, result: MXEventDecryptionResult) {
        listeners.forEach { listener in
            listener.onEventDecrypted(eventId: event.eventId, roomId: event.roomId, clearEvent: result.clearEvent)
        }
    }

    public func dispatchLiveEventDecryptionFailed(event: MXEvent, error: Error) {
        listeners.forEach { listener in
            listener.onEventDecryptionError(eventId: event.eventId, roomId: event.roomId, error: error)
        }
    }

    public func dispatchOnLiveToDevice(event: MXEvent) {
        listeners.forEach { listener in
            listener.onLiveToDeviceEvent(event: event)
        }
    }
}

