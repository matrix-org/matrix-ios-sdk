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

#import "MXKRecentTableViewCell.h"

#import "MXKRecentCellDataStoring.h"

#import "MXKRecentListDataSource.h"

@implementation MXKRecentTableViewCell

#pragma mark - Class methods
+ (UINib *)nib {
    return [UINib nibWithNibName:NSStringFromClass([MXKRecentTableViewCell class])
                          bundle:[NSBundle bundleForClass:[MXKRecentTableViewCell class]]];
}

- (NSString *) reuseIdentifier {
    return kMXKRecentCellIdentifier;
}

- (void)render:(MXKCellData *)cellData {

    id<MXKRecentCellDataStoring> roomCellData = (id<MXKRecentCellDataStoring>)cellData;
    if (roomCellData) {

        // Report computed values as is
        _roomTitle.text = roomCellData.roomDisplayname;
        _lastEventDescription.text = roomCellData.lastEventDescription;
        _lastEventDate.text = roomCellData.lastEventDate;

        // Set in bold public room name
        if (roomCellData.room.state.isPublic) {
            _roomTitle.font = [UIFont boldSystemFontOfSize:20];
        } else {
            _roomTitle.font = [UIFont systemFontOfSize:19];
        }

        // Set background color and unread count
        if (roomCellData.unreadCount) {
            if (roomCellData.containsBingUnread) {
                self.backgroundColor = [UIColor colorWithRed:0.9 green:0.9 blue:1 alpha:1.0];
            } else {
                self.backgroundColor = [UIColor colorWithRed:1 green:0.9 blue:0.9 alpha:1.0];
            }
            _roomTitle.text = [NSString stringWithFormat:@"%@ (%tu)", _roomTitle.text, roomCellData.unreadCount];
        } else {
            self.backgroundColor = [UIColor clearColor];
        }

    }
    else {
         _lastEventDescription.text = @"";
    }
}

+ (CGFloat)heightForCellData:(MXKCellData *)cellData withMaximumWidth:(CGFloat)maxWidth {

    // The height is fixed
    return 70;
}

@end
