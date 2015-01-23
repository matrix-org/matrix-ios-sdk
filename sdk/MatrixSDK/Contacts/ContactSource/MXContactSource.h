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

#import "MXContact.h"

/**
 Callback block that returns a list of contact.

 It provides a dictionary where the keys are the ids of the contacts in the contact source
 datastore and the values, the MXContact objects.
 
 In case of update, if a contact has been deleted, its MXContact value in the dictionnary must
 be set to NSNull.
 */
typedef void (^MXContactsCallbackBlock) (NSDictionary *contacts);

/**
 The `MXContactSource` protocol defines an interface that must be implemented in order to provide
 contacts to the MXContactManager.
 */
@protocol MXContactSource <NSObject>

/**
 The name of this contact source
 */
@property (nonatomic, readonly) NSString *name;

/**
 Get the list of contacts available on this system.
 
 The method is called on the main thread. Callback blocks must be called on this thread.

 @param success A block object called when the operation succeeds.
 @param failure A block object called when the operation fails.
 */
- (void)loadContacts:(MXContactsCallbackBlock)success failure:(void (^)(NSError *error))failure;

/**
 The listener of the source update.
 
 The implementation must call it once it has detected a change in its contacts.
 The `contacts` argument is the as in the loadContacts method except that it contains
 only contacts that have changed. 
 If a contact has been deleted, its MXContact value in the dictionnary must be set to NSNull.
 */
@property (nonatomic, strong) MXContactsCallbackBlock onUpdateListener;

@end
