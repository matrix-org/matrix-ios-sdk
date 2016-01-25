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

#import "MXCoreDataEvent+CoreDataProperties.h"

#ifdef MXCOREDATA_STORE

@implementation MXCoreDataEvent (CoreDataProperties)

@dynamic ageLocalTs;
@dynamic content;
@dynamic eventId;
@dynamic originServerTs;
@dynamic prevContent;
@dynamic redactedBecause;
@dynamic redacts;
@dynamic roomId;
@dynamic sender;
@dynamic stateKey;
@dynamic type;
@dynamic userId;
@dynamic room;

@end

#endif // MXCOREDATA_STORE
