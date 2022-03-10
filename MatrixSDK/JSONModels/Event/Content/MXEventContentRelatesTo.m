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

NSString *const kMXEventContentRelatesToKeyRelationType = @"rel_type";
NSString *const kMXEventContentRelatesToKeyEventId = @"event_id";
NSString *const kMXEventContentRelatesToKeyKey = @"key";
NSString *const kMXEventContentRelatesToKeyIsReplyFallback = @"is_falling_back";
NSString *const kMXEventContentRelatesToKeyInReplyTo = @"m.in_reply_to";

@interface MXEventContentRelatesTo()

@property (nonatomic, readwrite, nullable) NSString *relationType;
@property (nonatomic, readwrite, nullable) NSString *eventId;
@property (nonatomic, readwrite, nullable) NSString *key;
@property (nonatomic, readwrite) BOOL isReplyFallback;
@property (nonatomic, readwrite, nullable) MXInReplyTo *inReplyTo;

@end

@implementation MXEventContentRelatesTo

- (instancetype)initWithRelationType:(NSString *)relationType eventId:(NSString *)eventId
{
    return [self initWithRelationType:relationType eventId:eventId key:nil];
}

- (instancetype)initWithRelationType:(NSString *)relationType eventId:(NSString *)eventId key:(NSString *)key
{
    if (self = [super init])
    {
        _relationType = relationType;
        _eventId = eventId;
        _key = key;
        _isReplyFallback = NO;
    }
    
    return self;
}

#pragma mark - MXJSONModel

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXEventContentRelatesTo *relatesTo = [MXEventContentRelatesTo new];

    MXJSONModelSetString(relatesTo.relationType, JSONDictionary[kMXEventContentRelatesToKeyRelationType]);
    MXJSONModelSetString(relatesTo.eventId, JSONDictionary[kMXEventContentRelatesToKeyEventId]);
    MXJSONModelSetString(relatesTo.key, JSONDictionary[kMXEventContentRelatesToKeyKey]);
    MXJSONModelSetBoolean(relatesTo.isReplyFallback, JSONDictionary[kMXEventContentRelatesToKeyIsReplyFallback]);
    MXJSONModelSetMXJSONModel(relatesTo.inReplyTo, MXInReplyTo, JSONDictionary[kMXEventContentRelatesToKeyInReplyTo]);

    if (relatesTo.relationType || relatesTo.eventId || relatesTo.key || relatesTo.inReplyTo)
    {
        return relatesTo;
    }

    return nil;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];

    if (self.relationType)
    {
        JSONDictionary[kMXEventContentRelatesToKeyRelationType] = self.relationType;
    }
    if (self.eventId)
    {
        JSONDictionary[kMXEventContentRelatesToKeyEventId] = self.eventId;
    }
    if (self.key)
    {
        JSONDictionary[kMXEventContentRelatesToKeyKey] = self.key;
    }
    JSONDictionary[kMXEventContentRelatesToKeyIsReplyFallback] = @(self.isReplyFallback);
    if (self.inReplyTo)
    {
        JSONDictionary[kMXEventContentRelatesToKeyInReplyTo] = self.inReplyTo.JSONDictionary;
    }
    
    return JSONDictionary;
}
@end
