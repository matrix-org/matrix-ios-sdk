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

#define MXKROOMVIEWCONTROLLER_DEFAULT_TYPING_TIMEOUT_SEC 10

#import "MXKRoomViewController.h"

@interface MXKRoomViewController () {
    /**
     The data source providing UITableViewCells for the current room.
     */
    MXKRoomDataSource *dataSource;
    
    /**
     The input toolbar view
     */
    MXKRoomInputToolbarView *inputToolbarView;
    
    /**
     YES if scrolling to bottom is in progress
     */
    BOOL isScrollingToBottom;
    
    /**
     Date of the last observed typing
     */
    NSDate *lastTypingDate;
    /**
     Local typing timout
     */
    NSTimer* typingTimer;
}

@property (nonatomic) IBOutlet UITableView *tableView;
@property (nonatomic) IBOutlet UIView *roomInputToolbarContainer;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *roomInputToolbarContainerHeightConstraint;

@end

@implementation MXKRoomViewController

#pragma mark - Class methods

+ (UINib *)nib
{
    return [UINib nibWithNibName:NSStringFromClass([MXKRoomViewController class])
                          bundle:[NSBundle bundleForClass:[MXKRoomViewController class]]];
}

+ (instancetype)roomViewController
{
    return [[[self class] alloc] initWithNibName:NSStringFromClass([MXKRoomViewController class])
                                          bundle:[NSBundle bundleForClass:[MXKRoomViewController class]]];
}

#pragma mark -

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Check whether the view controller has been pushed via storyboard
    if (!_tableView) {
        // Instantiate view controller objects
        [[[self class] nib] instantiateWithOwner:self options:nil];
    }
    
    // Set default input toolbar view
    [self setRoomInputToolbarViewClass:MXKRoomInputToolbarView.class];
    
    // Check whether a room source has been defined
    if (dataSource) {
        [self configureView];
    }
}

- (void)dealloc {
    _tableView.dataSource = nil;
    _tableView.delegate = nil;
    _tableView = nil;
    dataSource = nil;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];

    // Dispose of any resources that can be recreated.
}

- (void)configureView {

    // Set up table data source
    _tableView.dataSource = dataSource;
    
    // Set up classes to use for cells
    [_tableView registerClass:[dataSource cellViewClassForCellIdentifier:kMXKIncomingRoomBubbleCellIdentifier] forCellReuseIdentifier:kMXKIncomingRoomBubbleCellIdentifier];
    [_tableView registerClass:[dataSource cellViewClassForCellIdentifier:kMXKOutgoingRoomBubbleCellIdentifier] forCellReuseIdentifier:kMXKOutgoingRoomBubbleCellIdentifier];

    // Start showing history right now
    [dataSource paginateBackMessagesToFillRect:self.view.frame success:^{
        // @TODO (hide loading wheel)
    } failure:^(NSError *error) {
        // @TODO
    }];
}

- (BOOL)isMessagesTableScrollViewAtTheBottom {
    
    // Check whether the most recent message is visible.
    // Compute the max vertical position visible according to contentOffset
    CGFloat maxPositionY = _tableView.contentOffset.y + (_tableView.frame.size.height - _tableView.contentInset.bottom);
    // Be a bit less retrictive, consider the table view at the bottom even if the most recent message is partially hidden
    maxPositionY += 30;
    BOOL isScrolledToBottom = (maxPositionY >= _tableView.contentSize.height);
    
    // Consider the table view at the bottom if a scrolling to bottom is in progress too
    return (isScrolledToBottom || isScrollingToBottom);
}

- (void)scrollMessagesTableViewToBottomAnimated:(BOOL)animated {
    
    if (_tableView.contentSize.height) {
        CGFloat visibleHeight = _tableView.frame.size.height - _tableView.contentInset.top - _tableView.contentInset.bottom;
        if (visibleHeight < _tableView.contentSize.height) {
            CGFloat wantedOffsetY = _tableView.contentSize.height - visibleHeight - _tableView.contentInset.top;
            CGFloat currentOffsetY = _tableView.contentOffset.y;
            if (wantedOffsetY != currentOffsetY) {
                isScrollingToBottom = YES;
                [_tableView setContentOffset:CGPointMake(0, wantedOffsetY) animated:animated];
            }
        }
    }
}

- (void)dismissKeyboard {
    [inputToolbarView dismissKeyboard];
}

#pragma mark -

- (void)displayRoom:(MXKRoomDataSource *)roomDataSource {

    dataSource = roomDataSource;
    dataSource.delegate = self;
    
    // Report the matrix session at view controller level to update UI according to session state
    self.mxSession = dataSource.mxSession;
    
    if (_tableView) {
        [self configureView];
    }
}

- (void)setRoomInputToolbarViewClass:(Class)roomInputToolbarViewClass {
    // Sanity check: accept only MXKRoomInputToolbarView classes or sub-classes
    NSParameterAssert([roomInputToolbarViewClass isSubclassOfClass:MXKRoomInputToolbarView.class]);
    
    // Remove potential toolbar
    if (inputToolbarView) {
        inputToolbarView.delegate = nil;
        [inputToolbarView removeFromSuperview];
    }
    inputToolbarView = [[roomInputToolbarViewClass alloc] init];
    inputToolbarView.delegate = self;
    
    // Add the input toolbar view and define edge constraints
    CGRect frame = _roomInputToolbarContainer.frame;
    frame.origin.x = 0;
    frame.origin.y = 0;
    inputToolbarView.frame = frame;
    [_roomInputToolbarContainer addSubview:inputToolbarView];
    [_roomInputToolbarContainer addConstraint:[NSLayoutConstraint constraintWithItem:_roomInputToolbarContainer
                                                     attribute:NSLayoutAttributeBottom
                                                     relatedBy:NSLayoutRelationEqual
                                                        toItem:inputToolbarView
                                                     attribute:NSLayoutAttributeBottom
                                                    multiplier:1.0f
                                                      constant:0.0f]];
    [_roomInputToolbarContainer addConstraint:[NSLayoutConstraint constraintWithItem:_roomInputToolbarContainer
                                                     attribute:NSLayoutAttributeTop
                                                     relatedBy:NSLayoutRelationEqual
                                                        toItem:inputToolbarView
                                                     attribute:NSLayoutAttributeTop
                                                    multiplier:1.0f
                                                      constant:0.0f]];
    [_roomInputToolbarContainer addConstraint:[NSLayoutConstraint constraintWithItem:_roomInputToolbarContainer
                                                     attribute:NSLayoutAttributeLeading
                                                     relatedBy:NSLayoutRelationEqual
                                                        toItem:inputToolbarView
                                                     attribute:NSLayoutAttributeLeading
                                                    multiplier:1.0f
                                                      constant:0.0f]];
    [_roomInputToolbarContainer addConstraint:[NSLayoutConstraint constraintWithItem:_roomInputToolbarContainer
                                                     attribute:NSLayoutAttributeTrailing
                                                     relatedBy:NSLayoutRelationEqual
                                                        toItem:inputToolbarView
                                                     attribute:NSLayoutAttributeTrailing
                                                    multiplier:1.0f
                                                      constant:0.0f]];
    [_roomInputToolbarContainer setNeedsUpdateConstraints];
}

#pragma mark - Back pagination

- (void)triggerBackPagination {
    // TODO: implement back pagination
}

#pragma mark - Post messages

- (void)sendMessage:(NSDictionary*)msgContent withLocalEvent:(MXEvent*)localEvent {
    MXMessageType msgType = msgContent[@"msgtype"];
    if (msgType) {
        // Check whether a temporary event has already been added for local echo (this happens on attachments)
        if (localEvent) {
//            // Look for this local event in messages
//            RoomMessage *message = [self messageWithEventId:localEvent.eventId];
//            if (message) {
//                // Update the local event with the actual msg content
//                localEvent.content = msgContent;
//                if (message.thumbnailURL) {
//                    // Reuse the current thumbnailURL as preview
//                    [localEvent.content setValue:message.thumbnailURL forKey:kRoomMessageLocalPreviewKey];
//                }
//                
//                if (message.messageType == RoomMessageTypeText) {
//                    [message removeEvent:localEvent.eventId];
//                    [message addEvent:localEvent withRoomState:self.mxRoom.state];
//                    if (!message.components.count) {
//                        [self removeMessage:message];
//                    }
//                } else {
//                    // Create a new message
//                    RoomMessage *aNewMessage = [[RoomMessage alloc] initWithEvent:localEvent andRoomState:self.mxRoom.state];
//                    if (aNewMessage) {
//                        [self replaceMessage:message withMessage:aNewMessage];
//                    } else {
//                        [self removeMessage:message];
//                    }
//                }
//            }
//            
//            [self.messagesTableView reloadData];
        } else {
            // Add a new local event
            localEvent = [self createLocalEchoEventWithoutContent];
            localEvent.content = msgContent;
            // TODO: MXKRoomDataSource must handle this pending event
//            [dataSource addLocalEchoEvent:localEvent];
        }
        
        // Send message to the room
        [dataSource.room sendMessageOfType:msgType content:msgContent success:^(NSString *eventId) {
            // We let the dataSource update the outgoing message status (pending to received) according to live event stream notification.
        } failure:^(NSError *error) {
            // TODO: Notify data source in order to remove the pending event
            
            NSLog(@"[MXKRoomVC] Post message failed: %@", error);
            // TODO: Alert user
//            [[AppDelegate theDelegate] showErrorAsAlert:error];
        }];
    }
}

- (void)sendTextMessage:(NSString*)msgTxt {
    MXMessageType msgType = kMXMessageTypeText;
    // Check whether the message is an emote
    if ([msgTxt hasPrefix:@"/me "]) {
        msgType = kMXMessageTypeEmote;
        // Remove "/me " string
        msgTxt = [msgTxt substringFromIndex:4];
    }
    
    [self sendMessage:@{@"msgtype":msgType, @"body":msgTxt} withLocalEvent:nil];
}

- (MXEvent*)createLocalEchoEventWithoutContent {
    // Create a temporary event to displayed outgoing message (local echo)
    NSString *localEventId = [NSString stringWithFormat:@"%@", [[NSProcessInfo processInfo] globallyUniqueString]];
    MXEvent *localEvent = [[MXEvent alloc] init];
    localEvent.roomId = dataSource.room.state.roomId;
    localEvent.eventId = localEventId;
    localEvent.type = kMXEventTypeStringRoomMessage;
    localEvent.originServerTs = (uint64_t) ([[NSDate date] timeIntervalSince1970] * 1000);
    
    localEvent.userId = dataSource.mxSession.myUser.userId;
    return localEvent;
}

#pragma mark - MXKDataSourceDelegate
- (void)dataSource:(MXKDataSource *)dataSource didChange:(id)changes {
    
    // For now, do a simple full reload
    [_tableView reloadData];
}

#pragma mark - UITableView delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    
    // Dismiss keyboard when user taps on messages table view content
    [self dismissKeyboard];
}

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath*)indexPath {
    
    // Release here resources, and restore reusable cells
    if ([cell conformsToProtocol:@protocol(MXKCellRendering)]) {
        [(id<MXKCellRendering>)cell didEndDisplay];
    }
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    
    // Detect vertical bounce at the top of the tableview to trigger pagination
    if (scrollView == _tableView) {
        // paginate ?
        if (scrollView.contentOffset.y < -64) {
            [self triggerBackPagination];
        }
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    
    // Consider this callback to reset scrolling to bottom flag
    isScrollingToBottom = NO;
}

#pragma mark - MXKRoomInputToolbarViewDelegate

- (void)roomInputToolbarView:(MXKRoomInputToolbarView*)toolbarView isTyping:(BOOL)typing {
    [self handleTypingNotification:typing];
}

- (void)roomInputToolbarView:(MXKRoomInputToolbarView*)toolbarView heightDidChanged:(CGFloat)height {
    _roomInputToolbarContainerHeightConstraint.constant = height;
    
    // Lays out the subviews immediately
    // We will scroll to bottom if the bottom of the table is currently visible
    BOOL shouldScrollToBottom = [self isMessagesTableScrollViewAtTheBottom];
    [self.view layoutIfNeeded];
    if (shouldScrollToBottom) {
        [self scrollMessagesTableViewToBottomAnimated:NO];
    }
}

- (void)roomInputToolbarView:(MXKRoomInputToolbarView*)toolbarView sendTextMessage:(NSString*)textMessage {
    [self sendTextMessage:textMessage];
}

- (void)roomInputToolbarView:(MXKRoomInputToolbarView*)toolbarView sendImage:(UIImage*)image{
    // TODO
}

- (void)roomInputToolbarView:(MXKRoomInputToolbarView*)toolbarView sendVideo:(NSURL*)videoURL withThumbnail:(UIImage*)videoThumbnail {
    // TODO
}

- (void)roomInputToolbarView:(MXKRoomInputToolbarView*)toolbarView inviteMatrixUser:(NSString*)mxUserId {
    [dataSource.room inviteUser:mxUserId success:^{
    } failure:^(NSError *error) {
        NSLog(@"[MXKRoomVC] Invite %@ failed: %@", mxUserId, error);
        // TODO: Alert user
//        [[AppDelegate theDelegate] showErrorAsAlert:error];
    }];
}

- (void)roomInputToolbarView:(MXKRoomInputToolbarView*)toolbarView presentMXKAlert:(MXKAlert*)alert {
    [alert showInViewController:self];
}

- (void)roomInputToolbarView:(MXKRoomInputToolbarView*)toolbarView presentMediaPicker:(UIImagePickerController*)mediaPicker {
    [self presentViewController:mediaPicker animated:YES completion:nil];
}

- (void)roomInputToolbarView:(MXKRoomInputToolbarView*)toolbarView dismissMediaPicker:(UIImagePickerController*)mediaPicker {
    if (self.presentedViewController == mediaPicker) {
        [self dismissViewControllerAnimated:NO completion:nil];
    }
}

# pragma mark - Typing notification

- (void)handleTypingNotification:(BOOL)typing {
    NSUInteger notificationTimeoutMS = -1;
    if (typing) {
        // Check whether a typing event has been already reported to server (We wait for the end of the local timout before considering this new event)
        if (typingTimer) {
            // Refresh date of the last observed typing
            lastTypingDate = [[NSDate alloc] init];
            return;
        }
        
        // Launch a timer to prevent sending multiple typing notifications
        NSTimeInterval timerTimeout = MXKROOMVIEWCONTROLLER_DEFAULT_TYPING_TIMEOUT_SEC;
        if (lastTypingDate) {
            NSTimeInterval lastTypingAge = -[lastTypingDate timeIntervalSinceNow];
            if (lastTypingAge < timerTimeout) {
                // Subtract the time interval since last typing from the timer timeout
                timerTimeout -= lastTypingAge;
            } else {
                timerTimeout = 0;
            }
        } else {
            // Keep date of this typing event
            lastTypingDate = [[NSDate alloc] init];
        }
        
        if (timerTimeout) {
            typingTimer = [NSTimer scheduledTimerWithTimeInterval:timerTimeout target:self selector:@selector(typingTimeout:) userInfo:self repeats:NO];
            // Compute the notification timeout in ms (consider the double of the local typing timeout)
            notificationTimeoutMS = 2000 * MXKROOMVIEWCONTROLLER_DEFAULT_TYPING_TIMEOUT_SEC;
        } else {
            // This typing event is too old, we will ignore it
            typing = NO;
            NSLog(@"[MXKRoomVC] Ignore typing event (too old)");
        }
    } else {
        // Cancel any typing timer
        [typingTimer invalidate];
        typingTimer = nil;
        // Reset last typing date
        lastTypingDate = nil;
    }
    
    // Send typing notification to server
    [dataSource.room sendTypingNotification:typing
                                timeout:notificationTimeoutMS
                                success:^{
                                    // Reset last typing date
                                    lastTypingDate = nil;
                                } failure:^(NSError *error) {
                                    NSLog(@"[MXKRoomVC] Failed to send typing notification (%d) failed: %@", typing, error);
                                    // Cancel timer (if any)
                                    [typingTimer invalidate];
                                    typingTimer = nil;
                                }];
}

- (IBAction)typingTimeout:(id)sender {
    [typingTimer invalidate];
    typingTimer = nil;
    
    // Check whether a new typing event has been observed
    BOOL typing = (lastTypingDate != nil);
    // Post a new typing notification
    [self handleTypingNotification:typing];
}

@end
