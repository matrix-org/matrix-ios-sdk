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

#import "MXStore.h"

#ifdef MXCOREDATA_STORE

/**
 `MXCoreDataStore` is an implementation of the `MXStore` interface based on Core Data.

 There is one DB (sqlite file) / core data instance per user. There is no relationships
 between these dbs.
 */
@interface MXCoreDataStore : NSObject <MXStore>

/**
 Erase all data
 */
+ (void)flush;

@end

#endif // MXCOREDATA_STORE
