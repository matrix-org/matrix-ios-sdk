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


public extension MXRoom {
    
    /**
     Send a generic non state event to a room.
     
     - parameters:
        - eventType: the type of the event.
        - content: the content that will be sent to the server as a JSON object.
        - localEcho: a pointer to an MXEvent object.
     
            When the event type is `MXEventType.roomMessage`, this pointer is set to an actual
            MXEvent object containing the local created event which should be used to echo the
            message in the messages list until the resulting event comes through the server sync.
            For information, the identifier of the created local event has the prefix:
            `kMXEventLocalEventIdPrefix`.
     
            You may specify nil for this parameter if you do not want this information.
     
            You may provide your own MXEvent object, in this case only its send state is updated.
     
            When the event type is `kMXEventTypeStringRoomEncrypted`, no local event is created.
     
        - completion: A block object called when the operation completes.
        - response: Provides the event id of the event generated on the home server on success
     
     - returns: a `MXHTTPOperation` instance.
     */
    @nonobjc @discardableResult func sendEvent(_ eventType: MXEventType, content: [String: Any], localEcho: inout MXEvent?, completion: @escaping (_ response: MXResponse<String?>) -> Void) -> MXHTTPOperation {
        
        let httpOperation = __sendEvent(ofType: eventType.identifier, content: content, localEcho: &localEcho, success: currySuccess(completion), failure: curryFailure(completion))
        return httpOperation!
    }

    
    
    
    /**
     Send a generic state event to a room.
     
     - parameters:
        - eventType: The type of the event.
        - content: the content that will be sent to the server as a JSON object.
        - completion: A block object called when the operation completes.
        - response: Provides the event id of the event generated on the home server on success.
     
     - returns: a `MXHTTPOperation` instance.
     */
    @nonobjc @discardableResult func sendStateEvent(_ eventType: MXEventType, content: [String: Any], completion: @escaping (_ response: MXResponse<String?>) -> Void) -> MXHTTPOperation {
        return __sendStateEvent(ofType: eventType.identifier, content: content, success: currySuccess(completion), failure: curryFailure(completion))
    }
    
    
    /**
     Send a room message to a room.
     
     - parameters:
        - content: the message content that will be sent to the server as a JSON object.
        - localEcho: a pointer to an MXEvent object.
     
            This pointer is set to an actual MXEvent object
            containing the local created event which should be used to echo the message in
            the messages list until the resulting event come through the server sync.
            For information, the identifier of the created local event has the prefix
            `kMXEventLocalEventIdPrefix`.
     
            You may specify nil for this parameter if you do not want this information.
     
            You may provide your own MXEvent object, in this case only its send state is updated.
     
        - completion: A block object called when the operation completes.
        - response: Provides the event id of the event generated on the home server on success
     
     - returns: a `MXHTTPOperation` instance.
     */
    @nonobjc @discardableResult func sendMessage(withContent content: [String: Any], localEcho: inout MXEvent?, completion: @escaping (_ response: MXResponse<String?>) -> Void) -> MXHTTPOperation {
        return __sendMessage(withContent: content, localEcho: &localEcho, success: currySuccess(completion), failure: curryFailure(completion))
    }
    
    
    
    /**
     Send a text message to the room.
     
     - parameters:
        - text: the text to send.
        - formattedText: the optional HTML formatted string of the text to send.
        - localEcho: a pointer to a MXEvent object.
     
            This pointer is set to an actual MXEvent object
            containing the local created event which should be used to echo the message in
            the messages list until the resulting event come through the server sync.
            For information, the identifier of the created local event has the prefix
            `kMXEventLocalEventIdPrefix`.

            You may specify nil for this parameter if you do not want this information.

            You may provide your own MXEvent object, in this case only its send state is updated.
     
        - completion: A block object called when the operation completes.
        - response: Provides the event id of the event generated on the home server on success.
     
     - returns: a `MXHTTPOperation` instance.
     */
    @nonobjc @discardableResult func sendTextMessage(_ text: String, formattedText: String? = nil, localEcho: inout MXEvent?, completion: @escaping (_ response: MXResponse<String?>) -> Void) -> MXHTTPOperation {
        return __sendTextMessage(text, formattedText: formattedText, localEcho: &localEcho, success: currySuccess(completion), failure: curryFailure(completion))
    }
    
    
    
    /**
     Send an emote message to the room.
     
     - parameters:
        - emoteBody: the emote body to send.
        - formattedBody: the optional HTML formatted string of the emote.
        - localEcho a pointer to a MXEvent object.
     
             This pointer is set to an actual MXEvent object
             containing the local created event which should be used to echo the message in
             the messages list until the resulting event come through the server sync.
             For information, the identifier of the created local event has the prefix
             `kMXEventLocalEventIdPrefix`.
             
             You may specify nil for this parameter if you do not want this information.
             
             You may provide your own MXEvent object, in this case only its send state is updated.
     
        - completion: A block object called when the operation completes.
        - response: Provides the event id of the event generated on the home server on success.
     
     - returns: a `MXHTTPOperation` instance.
     */
    @nonobjc @discardableResult func sendEmote(_ emote: String, formattedText: String? = nil, localEcho: inout MXEvent?, completion: @escaping (_ response: MXResponse<String?>) -> Void) -> MXHTTPOperation {
        return __sendEmote(emote, formattedText: formattedText, localEcho: &localEcho, success: currySuccess(completion), failure: curryFailure(completion))
    }
    
    
    

    /**
     Send an image to the room.

     - parameters:
        - imageData: the data of the image to send.
        - imageSize: the original size of the image.
        - mimetype:  the image mimetype.
        - thumbnail: optional thumbnail image (may be nil).
        - localEcho: a pointer to a MXEvent object.
     
             This pointer is set to an actual MXEvent object
             containing the local created event which should be used to echo the message in
             the messages list until the resulting event come through the server sync.
             For information, the identifier of the created local event has the prefix
             `kMXEventLocalEventIdPrefix`.
             
             You may specify nil for this parameter if you do not want this information.
             
             You may provide your own MXEvent object, in this case only its send state is updated.
     
        - completion: A block object called when the operation completes.
        - response: Provides the event id of the event generated on the home server on success.
     
     - returns: a `MXHTTPOperation` instance.
     */

    @nonobjc @discardableResult func sendImage(data imageData: Data, size: CGSize, mimeType: String, thumbnail: MXImage?, localEcho: inout MXEvent?, completion: @escaping (_ response: MXResponse<String?>) -> Void) -> MXHTTPOperation {
        return __sendImage(imageData, withImageSize: size, mimeType: mimeType, andThumbnail: thumbnail, localEcho: &localEcho, success: currySuccess(completion), failure: curryFailure(completion))
    }
    
    
    
    
    /**
     Send a video to the room.
     
     - parameters:
        - videoLocalURL: the local filesystem path of the video to send.
        - videoThumbnail: the UIImage hosting a video thumbnail.
        - localEcho: a pointer to a MXEvent object.
     
             This pointer is set to an actual MXEvent object
             containing the local created event which should be used to echo the message in
             the messages list until the resulting event come through the server sync.
             For information, the identifier of the created local event has the prefix
             `kMXEventLocalEventIdPrefix`.
             
             You may specify nil for this parameter if you do not want this information.
             
             You may provide your own MXEvent object, in this case only its send state is updated.
     
        - completion: A block object called when the operation completes.
        - response: Provides the event id of the event generated on the home server on success.
     
     - returns: a `MXHTTPOperation` instance.
     */
    @nonobjc @discardableResult func sendVideo(localURL: URL, thumbnail: MXImage?, localEcho: inout MXEvent?, completion: @escaping (_ response: MXResponse<String?>) -> Void) -> MXHTTPOperation {
        return __sendVideo(localURL, withThumbnail: thumbnail, localEcho: &localEcho, success: currySuccess(completion), failure: curryFailure(completion))
    }
    
    
    /**
     Send a file to the room.
 
     - parameters:
        - fileLocalURL: the local filesystem path of the file to send.
        - mimeType: the mime type of the file.
        - localEcho: a pointer to a MXEvent object.
     
             This pointer is set to an actual MXEvent object
             containing the local created event which should be used to echo the message in
             the messages list until the resulting event come through the server sync.
             For information, the identifier of the created local event has the prefix
             `kMXEventLocalEventIdPrefix`.
             
             You may specify nil for this parameter if you do not want this information.
             
             You may provide your own MXEvent object, in this case only its send state is updated.
     
        - completion: A block object called when the operation completes.
        - response: Provides the event id of the event generated on the home server on success.
     
     - returns: a `MXHTTPOperation` instance.
     */
    
    @nonobjc @discardableResult func sendFile(localURL: URL, mimeType: String, localEcho: inout MXEvent?, completion: @escaping (_ resposne: MXResponse<String?>) -> Void) -> MXHTTPOperation {
        return __sendFile(localURL, mimeType: mimeType, localEcho: &localEcho, success: currySuccess(completion), failure: curryFailure(completion))
    }
}

