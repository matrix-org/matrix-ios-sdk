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

#import "MX3PID.h"

/**
 The `MXContact` class provides few data but it is commonly available accross different contact sources.
 */
@interface MXContact : NSObject

/**
 The contact display name.
 */
@property (nonatomic) NSString *displayname;

/**
 The url of the avatar of the contact.
 */
@property (nonatomic) NSString *avatarUrl;

/**
 The list of MX3PIDs (msidsn numbers, email adresses, etc) the contact owns.
 */
@property (nonatomic) NSArray *MX3PIDs;

/**
 The list of Matrix user ids that match with the contact.
 The key of this dictionnary is a user id, the value is the MX3PID object in self.MX3PIDs
 that is linked to the user id.
 The value can be NSNull in case of pure Matrix contact.
 */
@property (nonatomic) NSDictionary *matrixUserIds;


@end
