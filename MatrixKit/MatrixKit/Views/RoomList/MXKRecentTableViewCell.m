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

@implementation MXKRecentTableViewCell

- (void)awakeFromNib {
    // Initialization code
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

- (void)render:(MXKCellData *)cellData {

    id<MXKRecentCellDataStoring> roomData = (id<MXKRecentCellDataStoring>)cellData;
    if (roomData) {
        self.textLabel.text = roomData.lastEventDescription;
    }
    else {
        self.textLabel.text = @"";
    }
}

@end
