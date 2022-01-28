/*
 Copyright 2019 New Vector Ltd

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

#import "MXEventContentRelatesTo.h"

static NSString* const kJSONInReplyTo = @"m.in_reply_to";

@interface MXEventContentRelatesTo()

@property (nonatomic, readwrite, nullable) MXInReplyTo *inReplyTo;

@end

@implementation MXEventContentRelatesTo

- (instancetype)initWithRelationType:(NSString *)relationType eventId:(NSString *)eventId
{
    return [self initWithRelationType:relationType eventId:eventId key:nil];
}

- (instancetype)initWithRelationType:(NSString *)relationType eventId:(NSString *)eventId key:(NSString *)key
{
    if (self = [super init]) {
        _relationType = relationType;
        _eventId = eventId;
        _key = key;
    }
    
    return self;
}

#pragma mark - MXJSONModel

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXEventContentRelatesTo *relatesTo;

    NSString *relationType;
    NSString *eventId;
    MXJSONModelSetString(relationType, JSONDictionary[@"rel_type"]);
    MXJSONModelSetString(eventId, JSONDictionary[@"event_id"]);

    if (relationType && eventId)
    {
        relatesTo = [MXEventContentRelatesTo new];
        relatesTo->_relationType = relationType;
        relatesTo->_eventId = eventId;

        MXJSONModelSetString(relatesTo->_key, JSONDictionary[@"key"]);
        MXJSONModelSetMXJSONModel(relatesTo.inReplyTo, MXInReplyTo, JSONDictionary[kJSONInReplyTo]);
    }

    return relatesTo;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
    
    JSONDictionary[@"rel_type"] = self.relationType;
    JSONDictionary[@"event_id"] = self.eventId;

    if (self.key)
    {
        JSONDictionary[@"key"] = self.key;
    }
    if (self.inReplyTo)
    {
        JSONDictionary[kJSONInReplyTo] = self.inReplyTo.JSONDictionary;
    }
    
    return JSONDictionary;
}
@end
