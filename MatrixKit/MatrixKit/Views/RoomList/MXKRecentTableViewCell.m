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
        _roomTitle.text = roomCellData.roomDisplayname;
        _lastEventDescription.text = roomCellData.lastEventDescription;
        _lastEventDate.text = roomCellData.lastEventDate;
    }
    else {
         _lastEventDescription.text = @"";
    }
}

+ (CGFloat)heightForCellData:(MXKCellData *)cellData withMaximumWidth:(CGFloat)maxWidth {
    return 70;
}

@end
