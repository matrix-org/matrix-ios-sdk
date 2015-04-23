/*
 Copyright 2015 OpenMarket Ltd

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

#import <AFNetworking/AFNetworking.h>

/**
 The `MXHTTPOperation` objects manage pending HTTP requests.

 They hold statitics on the requests so that the `MXHTTPClient` instance can apply
 retries policies.
 */
@interface MXHTTPOperation : NSObject

/**
 The underlying HTTP request.
 The reference changes in case of retries.
 */
@property (nonatomic) AFHTTPRequestOperation *operation;

/**
 The age in milliseconds of the instance.
 */
@property (nonatomic, readonly) NSUInteger age;

/**
 Number of times the request has been issued.
 */
@property (nonatomic) NSUInteger numberOfTries;

/**
 Max number of times the request can be retried.
 Default is 3.
 */
@property (nonatomic) NSUInteger maxNumberOfTries;

/**
 Time is milliseconds while a request can be retried.
 Default is 3 minutes.
 */
@property (nonatomic) NSUInteger maxRetriesTime;

/**
 Cancel the HTTP request.
 */
- (void)cancel;

@end
