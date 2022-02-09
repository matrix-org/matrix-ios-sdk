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

#import "NSDictionary+MutableDeepCopy.h"

@implementation NSDictionary (MutableDeepCopy)

- (NSMutableDictionary *)mutableDeepCopy
{
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:self.count];
    NSArray *keys = [self allKeys];

    for (id key in keys)
    {
        id object = [self objectForKey:key];
        id value = nil;
        if ([object conformsToProtocol:@protocol(MutableDeepCopying)])
        {
            value = [object mutableDeepCopy];
        }
        else if ([object conformsToProtocol:@protocol(NSMutableCopying)])
        {
            value = [object mutableCopy];
        }
        else if ([object conformsToProtocol:@protocol(NSCopying)])
        {
            value = [object copy];
        }
        else
        {
            value = object;
        }

        [result setValue:value forKey:key];
    }

    return result;
}

@end

@implementation NSArray (MutableDeepCopy)

-(NSMutableArray *)mutableDeepCopy
{
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:self.count];

    for (id object in self)
    {
        id value = nil;

        if ([object conformsToProtocol:@protocol(MutableDeepCopying)])
        {
            value = [object mutableDeepCopy];
        }
        else if ([object conformsToProtocol:@protocol(NSMutableCopying)])
        {
            value = [object mutableCopy];
        }
        else if ([object conformsToProtocol:@protocol(NSCopying)])
        {
            value = [object copy];
        }
        else
        {
            value = object;
        }

        [result addObject:value];
    }

    return result;
}

@end
