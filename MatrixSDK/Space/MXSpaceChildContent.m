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

#import "MXSpaceChildContent.h"

#pragma mark - Constants

static NSUInteger const kOrderValueMaxLength = 50;

// ASCII characters in the range \x20 (space) to \x7F (~)
static NSString* const kOrderTextRegexPattern = @"[ -~]+";

@implementation MXSpaceChildContent

#pragma mark - MXJSONModel

+ (instancetype)modelFromJSON:(NSDictionary *)JSONDictionary
{
    MXSpaceChildContent *spaceChildContent = [MXSpaceChildContent new];
    
    if (spaceChildContent)
    {
        NSString *parsedOrder;
        
        MXJSONModelSetString(parsedOrder, JSONDictionary[@"order"]);
        
        if ([self isOrderValid:parsedOrder])
        {
            spaceChildContent.order = parsedOrder;
        }
        
        MXJSONModelSetString(spaceChildContent.via, JSONDictionary[@"via"]);
        MXJSONModelSetBoolean(spaceChildContent.autoJoin, JSONDictionary[@"auto_join"])
        MXJSONModelSetBoolean(spaceChildContent.suggested, JSONDictionary[@"suggested"]);
    }

    return spaceChildContent;
}

- (NSDictionary *)JSONDictionary
{
    NSMutableDictionary *JSONDictionary = [NSMutableDictionary dictionary];
        
    if ([[self class] isOrderValid:self.order])
    {
        JSONDictionary[@"order"] = self.order;
    }
    else
    {
        MXLogDebug(@"[MXSpaceChildContent] JSONDictionary: order is not valid");
    }
    
    if (self.via)
    {
        JSONDictionary[@"via"] = self.via;
    }
    
    JSONDictionary[@"auto_join"] = @(self.autoJoin);
    JSONDictionary[@"suggested"] = @(self.suggested);
    
    return JSONDictionary;
}

#pragma mark - Private

/// Orders which are not strings, or do not consist solely of ascii characters in the range \x20 (space) to \x7F (~),
/// or consist of more than 50 characters, are forbidden and should be ignored if received.)
+ (BOOL)isOrderValid:(NSString*)order
{
    if (order.length == 0)
    {
        return YES;
    }
    
    if (order.length > kOrderValueMaxLength)
    {
        return NO;
    }
    
    static NSPredicate *predicate;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        predicate = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", kOrderTextRegexPattern];
    });

    return [predicate evaluateWithObject:order];
}

@end
