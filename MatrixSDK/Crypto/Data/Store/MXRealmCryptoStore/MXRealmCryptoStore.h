/*
 Copyright 2016 OpenMarket Ltd

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

#import "MXSDKOptions.h"

#ifdef MX_CRYPTO

#import "MXCryptoStore.h"

@interface MXRealmCryptoStore : NSObject <MXCryptoStore>

/**
 Flag to check if Realm DB compaction must be done.
 Default is YES.
 
 @discussion
 It may be useful to disable compaction when running on a different process than the main one in order
 to avoid race conditions.
 */
@property (class) BOOL shouldCompactOnLaunch;

/**
 Flag to control if Realm DB will be opened in read-only mode.
 Default is NO.
 */
@property (nonatomic, assign) BOOL readOnly;

@end

#endif
