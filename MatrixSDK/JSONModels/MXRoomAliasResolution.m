//
//  MXRoomAliasResolution.m
//  MatrixSDK
//
//  Created by Element on 28/03/2022.
//

#import <Foundation/Foundation.h>
#import "MXRoomAliasResolution.h"

@implementation MXRoomAliasResolution

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXRoomAliasResolution *resolution = [[MXRoomAliasResolution alloc] init];
    MXJSONModelSetString(resolution.roomId, JSONDictionary[@"room_id"]);
    MXJSONModelSetArray(resolution.servers, JSONDictionary[@"servers"])
    return resolution;
}

@end
