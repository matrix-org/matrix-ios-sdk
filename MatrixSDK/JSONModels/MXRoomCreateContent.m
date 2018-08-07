/*
 Copyright 2018 New Vector Ltd
 
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

#import "MXRoomCreateContent.h"

#pragma mark - Defines & Constants

static NSString* const kRoomCreateContentUserIdJSONKey = @"creator";
static NSString* const kRoomCreateContentPredecessorInfoJSONKey = @"predecessor";

#pragma mark - Private Interface

@interface MXRoomCreateContent()

@property (nonatomic, copy, readwrite, nonnull) NSString *creatorUserId;
@property (nonatomic, strong, readwrite, nullable) MXRoomPredecessorInfo *roomPredecessorInfo;

@end

@implementation MXRoomCreateContent

+ (id)modelFromJSON:(NSDictionary *)jsonDictionary
{
    MXRoomCreateContent *roomCreateContent = nil;
        
    NSString *roomCreatorUserId;
    MXJSONModelSetString(roomCreatorUserId, jsonDictionary[kRoomCreateContentUserIdJSONKey]);
    
    if (roomCreatorUserId)
    {
        roomCreateContent = [MXRoomCreateContent new];
        
        MXRoomPredecessorInfo *roomPredecessorInfo = nil;
        
        NSDictionary *roomPredecessorJSON = jsonDictionary[kRoomCreateContentPredecessorInfoJSONKey];
        
        if (roomPredecessorJSON)
        {
            roomPredecessorInfo = [MXRoomPredecessorInfo modelFromJSON:roomPredecessorJSON];
        }
        
        roomCreateContent.creatorUserId = roomCreatorUserId;
        roomCreateContent.roomPredecessorInfo = roomPredecessorInfo;
    }
    
    return roomCreateContent;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *jsonDictionary = [NSMutableDictionary dictionary];
    
    jsonDictionary[kRoomCreateContentUserIdJSONKey] = self.creatorUserId;
    
    if (self.roomPredecessorInfo)
    {
        jsonDictionary[kRoomCreateContentPredecessorInfoJSONKey] = [self.roomPredecessorInfo JSONDictionary];
    }
    
    return jsonDictionary;
}

@end
