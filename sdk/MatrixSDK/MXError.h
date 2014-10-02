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

typedef NSString* MXErrorCode;

@interface MXError : NSObject

@property (nonatomic, readonly) MXErrorCode errCode;
@property (nonatomic, readonly) NSString *error;

@property (nonatomic, readonly) NSError *nsError;

-(id)initWithErrorCode:(MXErrorCode)errCode error:(NSString*)error;
-(id)initWithNSError:(NSError*)nsError;

@end
