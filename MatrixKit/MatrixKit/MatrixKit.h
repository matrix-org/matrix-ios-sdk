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

#import "MXEvent+MatrixKit.h"

#import "MXKViewController.h"
#import "MXKRoomViewController.h"
#import "MXKRecentListViewController.h"

#import "MXKRoomInputToolbarView.h"
#import "MXKRoomInputToolbarViewWithHPGrowingText.h"

#import "MXKRoomDataSourceManager.h"

#import "MXKRoomBubbleCellData.h"
#import "MXKRoomBubbleMergingMessagesCellData.h"

/**
 The Matrix iOS Kit version.
 */
FOUNDATION_EXPORT NSString *MatrixKitVersion;