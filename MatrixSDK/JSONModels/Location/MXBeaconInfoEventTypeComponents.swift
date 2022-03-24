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

/// MXBeaconInfoEventTypeComponents handles beacon info event type string components. It makes the event type parsing and building easier.
@objcMembers
public class MXBeaconInfoEventTypeComponents: NSObject {
    
    // MARK: - Constants
    
    private enum Constants {
        static let separator: Character = "."
    }
    
    // MARK: - Properties
    
    // MARK: Private
    
    private static let eventTypeStringPrefix = kMXEventTypeStringBeaconInfoMSC3489

    // MARK: Public
    
    /// The event type string (i.e. "m.beacon_info)
    public let eventTypeString: String
    
    /// The event type unique suffix string (i.e. "@alice:matrix.org.0808090")
    public let uniqueSuffix: String
    
    /// User id from unique suffix if found (i.e. "@alice:matrix.org")
    public let userId: String?
    
    /// User id from unique suffix if found (i.e. "0808090")
    public let uniqueId: String?
    
    /// Generate "m.beacon_info" event type string with format "m.beacon_info.{userId}.{uniqueId}"
    public var fullEventTypeString: String {
        return "\(eventTypeString)\(Constants.separator)\(uniqueSuffix)"
    }
    
    // MARK: - Setup
    
    public init?(eventTypeString: String) {
        
        guard let (uniqueSuffix, userId, uniqueId) = type(of: self).getEventTypeComponents(from: eventTypeString) else {
            return nil
        }
        
        self.eventTypeString = MXBeaconInfoEventTypeComponents.eventTypeStringPrefix
        self.uniqueSuffix = uniqueSuffix
        self.userId = userId
        self.uniqueId = uniqueId
        
        super.init()
    }
    
    public init(uniqueSuffix: String) {
        self.eventTypeString = MXBeaconInfoEventTypeComponents.eventTypeStringPrefix
        self.uniqueSuffix = uniqueSuffix
        
        let (userId, uniqueId) = type(of: self).getComponents(fromUniqueSuffix: uniqueSuffix)
        
        self.userId = userId
        self.uniqueId = uniqueId
    }
    
    public init(userId: String, uniqueId: String) {
        self.eventTypeString = MXBeaconInfoEventTypeComponents.eventTypeStringPrefix
        
        self.uniqueSuffix = type(of: self).uniqueSuffix(from: userId, uniqueId: uniqueId)
        self.userId = userId
        self.uniqueId = uniqueId
        
        super.init()
    }
    
    public convenience init(userId: String) {
        self.init(userId: userId, uniqueId: UUID().uuidString)
    }
    
    // MARK: - Public
    
    public class func isEventTypeStringBeaconInfo(_ eventTypeString: String) -> Bool {
        return eventTypeString.hasPrefix(self.eventTypeStringPrefix)
    }
    
    // MARK: - Private
    
    private class func getEventTypeComponents(from eventTypeString: String) -> (String, String?, String?)? {
        
        guard self.isEventTypeStringBeaconInfo(eventTypeString) else {
            return nil
        }
        
        let separatorString = "\(Constants.separator)"
                        
        let eventTypeStringWithoutPrefix = String(eventTypeString.dropFirst(self.eventTypeStringPrefix.count))
        
        let uniqueSuffix: String
        
        // Remove the dot prefix of the suffix: ".@alice:matrix.org.0808090"
        if eventTypeStringWithoutPrefix.hasPrefix(separatorString) {
            uniqueSuffix = String(eventTypeStringWithoutPrefix.dropFirst(separatorString.count))
        } else {
            uniqueSuffix = eventTypeStringWithoutPrefix
        }
        
        let (userId, uniqueId) = self.getComponents(fromUniqueSuffix: uniqueSuffix)
        
        return (uniqueSuffix, userId, uniqueId)
    }
    
    private class func uniqueSuffix(from userId: String, uniqueId: String) -> String {
        return "\(userId)\(Constants.separator)\(uniqueId)"
    }
    
    // TODO: Try to retrieve user Id with MXTools.isMatrixUserIdentifierRegex and unique Id
    private class func getComponents(fromUniqueSuffix uniqueSuffix: String) -> (String?, String?) {
        let userId: String? = nil
        let uniqueId: String? = nil
        
        return (userId, uniqueId)
    }
}
