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
    // The class that inherits from MXJSONModel should declare its properties as they are
    // defined in the Matrix home server JSON response.
    // So, let Mantle do the mapping automatically
    return @{};
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionaryValue error:(NSError *__autoreleasing *)error
{
    // Do the JSON -> class instance properties mapping
    id instance = [super initWithDictionary:dictionaryValue error:error];
    
    // Store non declared JSON keys into the others property
    NSSet *propertyKeys = [self.class propertyKeys];
    for (NSString *key in dictionaryValue)
    {
        if ([propertyKeys containsObject:key])
        {
            if (nil == others)
            {
                others = [NSMutableDictionary dictionary];
            }
            others[key] = dictionaryValue[key];
        }
    }
    
    return instance;
}

-(NSDictionary *)others
{
    return others;
}
@end
