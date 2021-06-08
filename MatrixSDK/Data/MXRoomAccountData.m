/*
 Copyright 2015 OpenMarket Ltd

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

#import "MXRoomAccountData.h"

#import "MXEvent.h"
#import "MXRoomCreateContent.h"

@interface MXRoomAccountData ()

@property (nonatomic, readwrite) MXVirtualRoomInfo *virtualRoomInfo;

@end

@implementation MXRoomAccountData

- (void)handleEvent:(MXEvent *)event
{
    switch (event.eventType)
    {
        case MXEventTypeRoomTag:
            _tags = [MXRoomTag roomTagsWithTagEvent:event];
            break;
            
        case MXEventTypeReadMarker:
            MXJSONModelSetString(_readMarkerEventId, event.content[@"event_id"]);
            break;
            
        case MXEventTypeTaggedEvents:
        {
            MXJSONModelSetMXJSONModel(_taggedEvents, MXTaggedEvents, event.content);
            break;
        }
        case MXEventTypeCustom:
        {
            if ([event.type isEqualToString:kRoomIsVirtualJSONKey])
            {
                self.virtualRoomInfo = [MXVirtualRoomInfo modelFromJSON:event.content];
            }
            break;
        }

        default:
            break;
    }
}

- (MXTaggedEventInfo*)getTaggedEventInfo:(NSString*)eventId
             withTag:(NSString*)tag
{
    MXTaggedEventInfo *taggedEventInfo;
    MXJSONModelSetMXJSONModel(taggedEventInfo, MXTaggedEventInfo, _taggedEvents.tags[tag][eventId]);
    return taggedEventInfo;
}

- (NSArray<NSString *> *)getTaggedEventsIds:(NSString*)tag
{
    return _taggedEvents.tags[tag].allKeys;
}

#pragma mark - NSCoding
- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _tags = [aDecoder decodeObjectForKey:@"tags"];
        _readMarkerEventId = [aDecoder decodeObjectForKey:@"readMarkerEventId"];
        _taggedEvents = [aDecoder decodeObjectForKey:@"taggedEvents"];
        _virtualRoomInfo = [MXVirtualRoomInfo modelFromJSON:[aDecoder decodeObjectForKey:@"virtualRoomInfo"]];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_tags forKey:@"tags"];
    [aCoder encodeObject:_readMarkerEventId forKey:@"readMarkerEventId"];
    [aCoder encodeObject:_taggedEvents forKey:@"taggedEvents"];
    [aCoder encodeObject:_virtualRoomInfo.JSONDictionary forKey:@"virtualRoomInfo"];
}

@end
