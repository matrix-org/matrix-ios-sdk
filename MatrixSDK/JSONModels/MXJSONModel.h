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

#import <Foundation/Foundation.h>

/**
 A class that inherits from `MXJSONModel` represents the response to a request
 to a Matrix home server.
 
 Matrix home server responses are JSON strings. `MXJSONModel` derived classes map
 the members of the JSON object into their properties.
 
 Some of the methods below are pure virtual methods in C++ definition and must be
 implemented by the derived class if they are used by the code.
 */
@interface MXJSONModel : NSObject <NSCopying, NSCoding>


#pragma mark - Class methods
/**
 Create a model instance from a JSON dictionary.
 
 @param JSONDictionary the JSON data.
 @return the newly created instance.
 */
+ (id)modelFromJSON:(NSDictionary *)JSONDictionary;

/**
 Create model instances from an array of JSON dictionaries.
 
 @param JSONDictionaries the JSON data array.
 @return the newly created instances.
 */
+ (NSArray *)modelsFromJSON:(NSArray *)JSONDictionaries;

/**
 Clean a JSON dictionary by removing null values
 
 @param JSONDictionary the JSON data.
 @return JSON data without null values
 */
+ (NSDictionary *)removeNullValuesInJSON:(NSDictionary *)JSONDictionary;


#pragma mark - Instance methods
/**
 Rebuild the original JSON dictionary
 */
- (NSDictionary *)JSONDictionary;

/**
 This dictionary contains keys/values that have been in the JSON source object
 but not decoded.
 TODO: To implement so that app can manage custom events or paramaters.
 */
- (NSDictionary *)others;

@end
