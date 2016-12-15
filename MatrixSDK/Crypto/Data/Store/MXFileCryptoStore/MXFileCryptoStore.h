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

/**
 `MXFileCryptoStore` implements MXCryptoStore by storing crypto data on the
 file system.

 The files structure is the following:

    + NSCachesDirectory
        + MXFileCryptoStore
            + Matrix user id (one folder per account)
                L account: the user's olm account
                L devices: users devices keys
                L roomsAlgorithms: the algos used in rooms
                L sessions: the olm sessions with other users devices
                L inboundGroupSessions: the inbound group session
                L MXFileCryptoStore: Information about the stored data
 */
@interface MXFileCryptoStore : NSObject <MXCryptoStore>

/**
 Script to migrate to another storage.

 @param credentials the user account to migrate
 @return YES if successful.
 */
+ (BOOL)migrateToMXRealmCryptoStore:(MXCredentials *)credentials;

@end

#endif
