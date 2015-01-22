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

#import "MXContactSource.h"

#import "MXSession.h"

/**
 `MXMatrixContactSource` is an implementation of MXContactSource that allows to consider
 MXUsers as MXContacts. Thus, they can be displayed in an uniform way with other contacts
 from other systems.
 */
@interface MXMatrixContactSource : NSObject <MXContactSource>

/**
 Initialise the instance to list MXUsers of the passed MXSession instance.
 
 @param mxSession the Matrix session.
 @return the new instance.
 */
- (instancetype)initWithMXSession:(MXSession*)mxSession;

@end
