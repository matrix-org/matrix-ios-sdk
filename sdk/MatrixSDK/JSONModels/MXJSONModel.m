/*
 Copyright 2014 OpenMarket Ltd
 
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

#import "MXJSONModel.h"

@implementation MXJSONModel
{
    NSMutableDictionary *others;
}

+ (NSDictionary *)JSONKeyPathsByPropertyKey
{
    NSMutableDictionary *JSONKeyPathsByPropertyKey = [NSMutableDictionary dictionary];
    
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(?<=[a-z])([A-Z])|([A-Z])(?=[a-z])" options:0 error:nil];

    // List all properties defined by the class
    NSSet *propertyKeys = [self.class propertyKeys];
    for (NSString *propertyKey in propertyKeys)
    {
        // Manage camel-cased properties
        // Home server uses underscore-separated compounds keys like "event_id". ObjC properties name trend is more camelCase like "eventId".
        NSString *underscoredString = [[regex stringByReplacingMatchesInString:propertyKey options:0 range:NSMakeRange(0, propertyKey.length) withTemplate:@"_$1$2"] lowercaseString];
        JSONKeyPathsByPropertyKey[propertyKey] = underscoredString;
    }

    return JSONKeyPathsByPropertyKey;
}

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    // Use Mantle 
    id model = [MTLJSONAdapter modelOfClass:[self class]
                     fromJSONDictionary:JSONDictionary
                                  error:nil];
    
    // Put JSON keys not defined as class properties under the others dict
    [model setOthers:JSONDictionary];
    
    return model;
}

+ (NSArray *)modelsFromJSON:(NSArray *)JSONDictionaries
{
    NSMutableArray *models;
    
    for (NSDictionary *JSONDictionary in JSONDictionaries)
    {
        id model = [self modelFromJSON:JSONDictionary];
        if (model)
        {
            if (nil == models)
            {
                models = [NSMutableArray array];
            }
            
            [models addObject:model];
        }
    }
    return models;
}

+ (NSDictionary *)removeNullValuesInJSON:(NSDictionary *)JSONDictionary
{
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithDictionary:JSONDictionary];
    NSArray *keys = dictionary.allKeys;
    for (NSString *key in keys)
    {
        id value = dictionary[key];
        if ([value isEqual:[NSNull null]])
        {
            [dictionary removeObjectForKey:key];
        }
        else if ([value isKindOfClass:[NSDictionary class]])
        {
            [dictionary setObject:[MXJSONModel removeNullValuesInJSON:value] forKey:key];
        }
    }
    return dictionary;
}

- (void)setOthers:(NSDictionary *)JSONDictionary
{
    // Store non declared JSON keys into the others property
    NSArray *modelJSONKeys = [[self.class JSONKeyPathsByPropertyKey] allValues];
    for (NSString *key in JSONDictionary)
    {
        if (![modelJSONKeys containsObject:key])
        {
            if (nil == others)
            {
                others = [NSMutableDictionary dictionary];
            }
            others[key] = JSONDictionary[key];
        }
    }
}

-(NSDictionary *)others
{
    return others;
}

- (NSDictionary *)originalDictionary
{
    NSMutableDictionary * originalDictionary = [NSMutableDictionary dictionary];

    NSDictionary *JSONKeyPathsByPropertyKey = [self.class JSONKeyPathsByPropertyKey];

    for (NSString *key in self.dictionaryValue)
    {
        // Convert back camelCased property names (ex:roomId) to underscored names (ex:room_id)
        // Thus, we store events as they come from the home server
        originalDictionary[JSONKeyPathsByPropertyKey[key]] = self.dictionaryValue[key];
    }

    return originalDictionary;
}

@end
