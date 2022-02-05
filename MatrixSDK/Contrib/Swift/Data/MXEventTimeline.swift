/*
 Copyright 2017 Avery Pierce
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

import Foundation

public extension MXEventTimeline {
    
    /**
     Reset the pagination timelime and start loading the context around its `initialEventId`.
     The retrieved (backwards and forwards) events will be sent to registered listeners.
     
     - parameters:
        - limit: the maximum number of messages to get around the initial event.
        - completion: A block object called when the operation completes.
        - response: Indicates whether the operation succeeded or failed.
     
     - returns: a `MXHTTPOperation` instance.
     */
    @discardableResult func resetPaginationAroundInitialEvent(withLimit limit: UInt, completion: @escaping (_ response: MXResponse<Void>) -> Void) -> MXHTTPOperation {
        return __resetPaginationAroundInitialEvent(withLimit: limit, success: currySuccess(completion), failure: curryFailure(completion))
    }
    
    /**
     Get more messages.
     The retrieved events will be sent to registered listeners.
     
     Note it is not possible to paginate forwards on a live timeline.
     
     - parameters:
        - numItems: the number of items to get.
        - direction: `.forwards` or `.backwards`.
        - onlyFromStore: if true, return available events from the store, do not make a pagination request to the homeserver.
        - completion: A block object called when the operation completes.
        - response: Indicates whether the operation succeeded or failed.
     
     - returns: a MXHTTPOperation instance. This instance can be nil if no request to the homeserver is required.
     */
    @discardableResult func paginate(_ numItems: UInt, direction: MXTimelineDirection, onlyFromStore: Bool, completion: @escaping (_ response: MXResponse<Void>) -> Void) -> MXHTTPOperation? {
        return __paginate(numItems, direction: direction, onlyFromStore: onlyFromStore, complete: currySuccess(completion), failure: curryFailure(completion))
    }
    
    
    
    /**
     Register a listener to events of this timeline.
     
     - parameters:
        - types: an array of event types to listen to
        - block: the block that will called once a new event has been handled.
     - returns: a reference to use to unregister the listener
     */
    func listenToEvents(_ types: [MXEventType]? = nil, _ block: @escaping MXOnRoomEvent) -> Any {
        
        if let types = types {
            let typeStrings = types.map({ return $0.identifier })
            return __listen(toEventsOfTypes: typeStrings, onEvent: block)
        } else {
            return __listen(toEvents: block)
        }
    }
}
