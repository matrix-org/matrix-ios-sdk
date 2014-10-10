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

#import <Mantle/Mantle.h>

/**
 A class that inherits from `MXJSONModel` represents the response to a request to a Matrix home server.
 
 Matrix home server responses are a JSON string. The `MXJSONModel` class maps the members in the JSON object to the properties declared in the class that inherits from MXJSONModel
 */
@interface MXJSONModel : MTLModel <MTLJSONSerializing>

    /**
     This dictionary contains keys/values that have been in the JSON source object.
     */
    @property (nonatomic, readonly) NSDictionary *others;

@end
