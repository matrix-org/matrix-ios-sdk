// 
// Copyright 2020 The Matrix.org Foundation C.I.C
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

#import "MXTaggedEvents.h"

NSString *const kMXTaggedEventFavourite = @"m.favourite";
NSString *const kMXTaggedEventHidden = @"m.hidden";

@implementation MXTaggedEvents

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXTaggedEvents *taggedEvents = [[MXTaggedEvents alloc] init];
    if (taggedEvents)
    {
        MXJSONModelSetDictionary(taggedEvents.tags, JSONDictionary[@"tags"]);
    }
    
    return taggedEvents;
}

- (NSDictionary*)JSONDictionary
{
    NSMutableDictionary *jsonDictionary = [NSMutableDictionary dictionary];
    
    jsonDictionary[@"tags"] = _tags;
    
    return jsonDictionary;
}

- (void)tagEvent:(NSString *)eventId taggedEventInfo:(MXTaggedEventInfo *)info tag:(NSString *)tag
{
    NSMutableDictionary<NSString*, NSDictionary<NSString*, NSDictionary*>* > *updatedTags = [_tags mutableCopy];
    if (!updatedTags)
    {
        updatedTags = [NSMutableDictionary dictionary];
    }
    
    NSMutableDictionary<NSString*, NSDictionary*> *tagDict = [_tags[tag] mutableCopy];
    if (!tagDict)
    {
        tagDict = [NSMutableDictionary dictionary];
    }
    tagDict[eventId] = info.JSONDictionary;
    
    updatedTags[tag] = tagDict;
    
    _tags = updatedTags;
}

- (void)untagEvent:(NSString *)eventId tag:(NSString *)tag
{
    NSMutableDictionary<NSString*, NSDictionary<NSString*, NSDictionary*>* > *updatedTags = [_tags mutableCopy];
    if (updatedTags)
    {
        NSMutableDictionary<NSString*, NSDictionary*> *tagDict = [_tags[tag] mutableCopy];
        if (tagDict)
        {
            [tagDict removeObjectForKey:eventId];
            
            if (tagDict.count == 0)
            {
                [updatedTags removeObjectForKey:tag];
            }
            else
            {
                updatedTags[tag] = tagDict;
            }
            
            _tags = updatedTags;
        }
    }
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super init];
    if (self)
    {
        _tags = [aDecoder decodeObjectForKey:@"tags"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:_tags forKey:@"tags"];
}

@end
