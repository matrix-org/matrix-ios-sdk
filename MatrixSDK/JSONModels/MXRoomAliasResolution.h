//
//  MXRoomAliasResolution.h
//  Pods
//
//  Created by Element on 28/03/2022.
//

#ifndef MXRoomAliasResolution_h
#define MXRoomAliasResolution_h

#import "MXJSONModel.h"

/**
 The result of a server resolving a room alias via /directory/room/ endpoint
 into a cannonical identifier with servers that are aware of this identifier.
 */
@interface MXRoomAliasResolution : MXJSONModel

/**
 Resolved room identifier that matches a given alias
 */
@property (nonatomic, strong) NSString *roomId;

/**
 A list of servers that are aware of the room identifier.
 */
@property (nonatomic, strong) NSArray<NSString *> *servers;

@end

#endif /* MXRoomAliasResolution_h */
