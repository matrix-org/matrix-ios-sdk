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

#import "MXKRoomOutgoingBubbleTableViewCell.h"

#import "MXEvent+MatrixKit.h"

@implementation MXKRoomOutgoingBubbleTableViewCell


- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        NSArray *nibViews = [[NSBundle bundleForClass:[MXKRoomOutgoingBubbleTableViewCell class]] loadNibNamed:NSStringFromClass([MXKRoomOutgoingBubbleTableViewCell class])
                                                                                                         owner:self
                                                                                                       options:nil];
        
        UIView *nibContentView = nibViews.firstObject;
        nibContentView.frame = self.contentView.frame;
        [self.contentView addSubview:nibContentView];
    }
    return self;
}


- (void)dealloc {
    [self stopAnimating];
}

- (void)render:(MXKCellData *)cellData {
    [super render:cellData];
    
    if (self.bubbleData) {
        // Add unsent label for failed components
        [self.bubbleData prepareBubbleComponentsPosition];
        for (MXKRoomBubbleComponent *component in self.bubbleData.bubbleComponents) {
            if (component.event.mxkState == MXKEventStateSendingFailed) {
                UIButton *unsentButton = [[UIButton alloc] initWithFrame:CGRectMake(0, component.position.y, 58 , 20)];
                
                [unsentButton setTitle:@"Unsent" forState:UIControlStateNormal];
                [unsentButton setTitle:@"Unsent" forState:UIControlStateSelected];
                [unsentButton setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
                [unsentButton setTitleColor:[UIColor redColor] forState:UIControlStateSelected];
                
                unsentButton.backgroundColor = [UIColor whiteColor];
                unsentButton.titleLabel.font =  [UIFont systemFontOfSize:14];
                
                // add a dummy label to store the event ID
                // so the message will be easily found when the button will be tapped
                UILabel* hiddenLabel = [[UILabel alloc] init];
                hiddenLabel.tag = 4; // TODO GFO ROOM_MESSAGE_CELL_HIDDEN_UNSENT_MSG_LABEL_TAG;
                hiddenLabel.text = component.event.eventId;
                hiddenLabel.hidden = YES;
                hiddenLabel.frame = CGRectZero;
                hiddenLabel.userInteractionEnabled = YES;
                [unsentButton addSubview:hiddenLabel];
                
                // TODO GFO [unsentButton addTarget:self action:@selector(onResendToggle:) forControlEvents:UIControlEventTouchUpInside];
                
                [self.dateTimeLabelContainer addSubview:unsentButton];
                self.dateTimeLabelContainer.hidden = NO;
                self.dateTimeLabelContainer.userInteractionEnabled = YES;
                
                // ensure that dateTimeLabelContainer is at front to catch the the tap event
                [self.dateTimeLabelContainer.superview bringSubviewToFront:self.dateTimeLabelContainer];
            }
        }
        
        // wait after upload info
        if (self.bubbleData.isUploadInProgress) {
            [self startUploadAnimating];
            self.attachmentView.hideActivityIndicator = YES;
        } else {
            self.attachmentView.hideActivityIndicator = NO;
        }
    }
}

- (void)didEndDisplay {
    [super didEndDisplay];
    
    // Hide potential loading wheel
    [self stopAnimating];
}

-(void)startUploadAnimating {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kMXKMediaUploadProgressNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onUploadProgress:) name:kMXKMediaUploadProgressNotification object:nil];
    
    self.activityIndicator.hidden = NO;
    [self.activityIndicator startAnimating];
    
    MXKMediaLoader *uploader = [MXKMediaManager existingUploaderWithId:self.bubbleData.uploadId];
    if (uploader && uploader.statisticsDict) {
        [self.activityIndicator stopAnimating];
        [self updateProgressUI:uploader.statisticsDict];
        
        // Check whether the upload is ended
        if (self.progressChartView.progress == 1.0) {
            self.progressView.hidden = YES;
        }
    } else {
        self.progressView.hidden = YES;
    }
}


-(void)stopAnimating {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kMXKMediaUploadProgressNotification object:nil];
    [self.activityIndicator stopAnimating];
}

- (void)onUploadProgress:(NSNotification *)notif {
    // sanity check
    if ([notif.object isKindOfClass:[NSString class]]) {
        NSString *uploadId = notif.object;
        if ([uploadId isEqualToString:self.bubbleData.uploadId]) {
            [self.activityIndicator stopAnimating];
            [self updateProgressUI:notif.userInfo];
            
            // the upload is ended
            if (self.progressChartView.progress == 1.0) {
                self.progressView.hidden = YES;
            }
        }
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    // ensure that the text is still aligned to the left side of the screen
    // even during animation while enlarging/reducing the viewcontroller (with UISplitViewController)
    CGFloat leftInset = self.bubbleData.maxTextViewWidth -  self.bubbleData.contentSize.width;
    self.messageTextView.contentInset = UIEdgeInsetsMake(0, leftInset, 0, -leftInset);
}

@end