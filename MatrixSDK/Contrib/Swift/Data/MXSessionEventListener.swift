//
//  MXSessionEventListener.swift
//  MatrixSDK
//
//  Created by Avery Pierce on 7/12/17.
//  Copyright © 2017 matrix.org. All rights reserved.
//

import Foundation

/**
 Block called when an event of the registered types has been handled by the `MXSession` instance.
 This is a specialisation of the `MXOnEvent` block.
 
 - parameters:
    - event: the new event.
    - direction: the origin of the event.
    - customObject: additional contect for the event. In case of room event, `customObject` is a `RoomState` instance. In the case of a presence, `customObject` is `nil`.
 */
public typealias MXOnSessionEvent = (_ event: MXEvent, _ direction: MXTimelineDirection, _ customObject: Any?) -> Void;
