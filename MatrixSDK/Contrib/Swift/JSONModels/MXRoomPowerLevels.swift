//
//  MXRoomPowerLevels.swift
//  MatrixSDK
//
//  Created by Avery Pierce on 7/24/17.
//  Copyright © 2017 matrix.org. All rights reserved.
//

import Foundation

extension MXRoomPowerLevels {
    
    /**
     Helper to get the minimum power level the user must have to send an event of the given type
     as a message.
     
     - parameter eventType: the type of event.
     - returns: the required minimum power level.
     */
    @nonobjc func minimumPowerLevelForSendingMessageEvent(_ eventType: MXEventType) -> Int {
        return __minimumPowerLevelForSendingEvent(asMessage: eventType.identifier)
    }
    
    /**
     Helper to get the minimum power level the user must have to send an event of the given type
     as a state event.
     
     - parameter eventType: the type of event.
     - returns: the required minimum power level.
     */
    @nonobjc func minimumPowerLevelForSendingStateEvent(_ eventType: MXEventType) -> Int {
        return __minimumPowerLevelForSendingEvent(asStateEvent: eventType.identifier)
    }
    
}
