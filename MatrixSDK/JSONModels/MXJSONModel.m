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

/**
 * The JSONKeyPathsByPropertyKey dictionnaries for all subclasses of MXJSONModel.
 * The key is the child class name. The value, the JSONKeyPathsByPropertyKey dictionnary of the child class.
 */
static NSMutableDictionary *JSONKeyPathsByPropertyKeyByClass;

+ (void)initialize
{
    @synchronized(JSONKeyPathsByPropertyKeyByClass)
    {
        if (!JSONKeyPathsByPropertyKeyByClass)
        {
            JSONKeyPathsByPropertyKeyByClass = [NSMutableDictionary dictionary];
        }

        // Compute the JSONKeyPathsByPropertyKey for this subclass
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

        JSONKeyPathsByPropertyKeyByClass[NSStringFromClass(self.class)] = JSONKeyPathsByPropertyKey;
    }
}

+ (NSDictionary *)JSONKeyPathsByPropertyKey
{
    return JSONKeyPathsByPropertyKeyByClass[NSStringFromClass(self.class)];
}

+ (id)modelFromJSON:(NSDictionary *)JSONDictionary
{
    // Use Mantle 
    id model = [MTLJSONAdapter modelOfClass:[self class]
                     fromJSONDictionary:JSONDictionary
                                  error:nil];
    
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
    // A new dictionary is created and returned only if necessary
    NSMutableDictionary *dictionary;

    for (NSString *key in JSONDictionary)
    {
        id value = JSONDictionary[key];
        if ([value isEqual:[NSNull null]])
        {
            if (!dictionary)
            {
               dictionary = [NSMutableDictionary dictionaryWithDictionary:JSONDictionary];
            }

            [dictionary removeObjectForKey:key];
        }
        else if ([value isKindOfClass:[NSDictionary class]])
        {
            NSDictionary *subDictionary = [MXJSONModel removeNullValuesInJSON:value];
            if (subDictionary != value)
            {
                if (!dictionary)
                {
                    dictionary = [NSMutableDictionary dictionaryWithDictionary:JSONDictionary];
                }

                dictionary[key] = subDictionary;

            }
        }
        else if ([value isKindOfClass:[NSArray class]])
        {
            // Check dictionaries in this array
            NSArray *arrayValue = value;
            NSMutableArray *newArrayValue;

            for (NSInteger i = 0; i < arrayValue.count; i++)
            {
                NSObject *arrayItem = arrayValue[i];

                if ([arrayItem isKindOfClass:[NSDictionary class]])
                {
                    NSDictionary *subDictionary = [MXJSONModel removeNullValuesInJSON:(NSDictionary*)arrayItem];
                    if (subDictionary != arrayItem)
                    {
                        // This dictionary need to be sanitised. Update its parent array
                        if (!newArrayValue)
                        {
                            newArrayValue = [NSMutableArray arrayWithArray:arrayValue];
                        }

                        [newArrayValue replaceObjectAtIndex:i withObject:subDictionary];
                    }
                }
            }

            if (newArrayValue)
            {
                // The array has changed, update it in the dictionary
                if (!dictionary)
                {
                    dictionary = [NSMutableDictionary dictionaryWithDictionary:JSONDictionary];
                }

                dictionary[key] = newArrayValue;
            }
        }
    }

    if (dictionary)
    {
        return dictionary;
    }
    else
    {
        return JSONDictionary;
    }
}

- (NSDictionary *)originalDictionary
{
    NSMutableDictionary * originalDictionary = [NSMutableDictionary dictionary];

    NSDictionary *JSONKeyPathsByPropertyKey = [self.class JSONKeyPathsByPropertyKey];
    NSDictionary *dictValue = self.dictionaryValue;
    
    for (NSString *key in dictValue)
    {
        // Ignore NSNull values introduced by dictionaryWithValuesForKeys use in 'dictionaryValue' getter.
        if (![dictValue[key] isKindOfClass:[NSNull class]])
        {
            // Convert back camelCased property names (ex:roomId) to underscored names (ex:room_id)
            // Thus, we store events as they come from the home server.
            originalDictionary[JSONKeyPathsByPropertyKey[key]] = dictValue[key];
        }
    }

    return originalDictionary;
}

@end
