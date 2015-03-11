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

#import "MXKSampleJSQRoomDataSource.h"
#import "MXKSampleJSQRoomBubbleCellData.h"


@implementation MXKSampleJSQRoomDataSource

- (instancetype)initWithRoom:(MXRoom *)aRoom andMatrixSession:(MXSession *)session {
    
    self = [super initWithRoom:aRoom andMatrixSession:session];
    if (self) {
        // Change data classes
        [self registerCellDataClass:MXKSampleJSQRoomBubbleCellData.class forCellIdentifier:kMXKIncomingRoomBubbleCellIdentifier];
        [self registerCellDataClass:MXKSampleJSQRoomBubbleCellData.class forCellIdentifier:kMXKOutgoingRoomBubbleCellIdentifier];
    }
    return self;
}

- (id<JSQMessageData>)collectionView:(JSQMessagesCollectionView *)collectionView messageDataForItemAtIndexPath:(NSIndexPath *)indexPath {
    
    id<JSQMessageData> messageData;
    @synchronized(bubbles) {
        messageData = bubbles[indexPath.item];
    }
    return messageData;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    
    NSInteger count;
    @synchronized(bubbles) {
        count = bubbles.count;
    }
    return count;
}

@end
