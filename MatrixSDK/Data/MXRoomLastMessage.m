// 
// Copyright 2021 The Matrix.org Foundation C.I.C
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

#import "MXRoomLastMessage.h"

NSString *const kCodingKeyEventId = @"eventId";
NSString *const kCodingKeyOriginServerTs = @"originServerTs";

@interface MXRoomLastMessage ()

@property (nonatomic, copy, readwrite) NSString *eventId;

@property (nonatomic, assign, readwrite) uint64_t originServerTs;

@end

@implementation MXRoomLastMessage

- (instancetype)initWithEventId:(NSString *)eventId originServerTs:(uint64_t)originServerTs
{
    if (self = [super init])
    {
        self.eventId = eventId;
        self.originServerTs = originServerTs;
    }
    return self;
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder
{
    if (self = [super init])
    {
        self.eventId = [coder decodeObjectForKey:kCodingKeyEventId];
        self.originServerTs = [coder decodeInt64ForKey:kCodingKeyOriginServerTs];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_eventId forKey:kCodingKeyEventId];
    [coder encodeInt64:_originServerTs forKey:kCodingKeyOriginServerTs];
}

@end
