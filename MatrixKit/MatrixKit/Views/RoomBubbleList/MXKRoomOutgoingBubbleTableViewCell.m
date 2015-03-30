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
    NSArray *nibViews = [[NSBundle bundleForClass:[MXKRoomOutgoingBubbleTableViewCell class]] loadNibNamed:NSStringFromClass([MXKRoomOutgoingBubbleTableViewCell class])
                                                                                                     owner:nil
                                                                                                   options:nil];
    self = nibViews.firstObject;
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
                
                [unsentButton addTarget:self action:@selector(onResendToggle:) forControlEvents:UIControlEventTouchUpInside];
                
                [self.dateTimeLabelContainer addSubview:unsentButton];
                self.dateTimeLabelContainer.hidden = NO;
                self.dateTimeLabelContainer.userInteractionEnabled = YES;
                
                // ensure that dateTimeLabelContainer is at front to catch the tap event
                [self.dateTimeLabelContainer.superview bringSubviewToFront:self.dateTimeLabelContainer];
            }
        }

        if (self.attachmentView) {

            // Check if the image is uploading
            MXKRoomBubbleComponent *component = self.bubbleData.bubbleComponents.firstObject;
            if (MXKEventStateUploading == component.event.mxkState) {

                // Retrieve the uploadId embedded in the fake url
                self.bubbleData.uploadId = component.event.content[@"url"];

                // And start showing upload progress
                [self startUploadAnimating];
                self.attachmentView.hideActivityIndicator = YES;
            }
            else {

                self.attachmentView.hideActivityIndicator = NO;
            }
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

#pragma mark - User actions

- (IBAction)onResendToggle:(id)sender {
    
    if ([sender isKindOfClass:[UIButton class]] && self.delegate) {
        
        MXEvent *selectedEvent = nil;
        if (self.bubbleData.bubbleComponents.count == 1) {
            MXKRoomBubbleComponent *component = [self.bubbleData.bubbleComponents firstObject];
            selectedEvent = component.event;
        } else if (self.bubbleData.bubbleComponents.count) {
            // Here the selected view is a textView (attachment has no more than one component)
            
            // Look for the selected component
            UIButton *unsentButton = (UIButton *)sender;
            for (MXKRoomBubbleComponent *component in self.bubbleData.bubbleComponents) {
                if (unsentButton.frame.origin.y == component.position.y) {
                    selectedEvent = component.event;
                    break;
                }
            }
        }
        
        if (selectedEvent) {
            [self.delegate cell:self didRecognizeAction:kMXKRoomBubbleCellUnsentButtonPressed userInfo:@{kMXKRoomBubbleCellEventKey:selectedEvent}];
        }
    }
}

@end