/*
 Copyright 2016 OpenMarket Ltd
 
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

#import "MXRoomEventFilter.h"

@interface MXRoomEventFilter()
{
    NSMutableDictionary<NSString *, id> *dictionary;
}
@end

@implementation MXRoomEventFilter

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        dictionary = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)setContainsURL:(BOOL)containsURL
{
    dictionary[@"contains_url"] = [NSNumber numberWithBool:containsURL];
    _containsURL = containsURL;
}

- (void)setTypes:(NSArray<NSString *> *)types
{
    dictionary[@"types"] = types;
    _types = types;
}

- (void)setNotTypes:(NSArray<NSString *> *)notTypes
{
    dictionary[@"not_types"] = notTypes;
    _notTypes = notTypes;
}

- (void)setRooms:(NSArray<NSString *> *)rooms
{
    dictionary[@"rooms"] = rooms;
    _rooms = rooms;
}

- (void)setNotRooms:(NSArray<NSString *> *)notRooms
{
    dictionary[@"not_rooms"] = notRooms;
    _notRooms = notRooms;
}

- (void)setSenders:(NSArray<NSString *> *)senders
{
    dictionary[@"senders"] = senders;
    _senders = senders;
}

- (void)setNotSenders:(NSArray<NSString *> *)notSenders
{
    dictionary[@"not_senders"] = notSenders;
    _notSenders = notSenders;
}

- (void)setLimit:(NSUInteger)limit
{
    dictionary[@"limit"] = [NSNumber numberWithUnsignedInteger:limit];
}

- (NSDictionary<NSString *, id>*)dictionary
{
    return dictionary;
}

@end
