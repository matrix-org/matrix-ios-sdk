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

#import <UIKit/UIKit.h>

#import "MXKViewController.h"
#import "MXKRecentListDataSource.h"

@class MXKRecentListViewController;

/**
 `MXKRecentListViewController` delegate.
 */
@protocol MXKRecentListViewControllerDelegate <NSObject>

/**
 Tells the delegate that the user selected a room.

 @param recentListViewController the `MXKRecentListViewController` instance.
 @param roomId the id of the selected room.
 */
- (void)recentListViewController:(MXKRecentListViewController *)recentListViewController didSelectRoom:(NSString*)roomId;

@end


/**
 This view controller displays messages of a room.
 */
@interface MXKRecentListViewController : MXKViewController <MXKDataSourceDelegate, UITableViewDelegate>

/**
 The delegate for the view controller.
 */
@property (nonatomic) id<MXKRecentListViewControllerDelegate> delegate;

/**
 Display the recent list.

 @param listDataSource the data source providing the recents list.
 */
- (void)displayList:(MXKRecentListDataSource*)listDataSource;

@end
