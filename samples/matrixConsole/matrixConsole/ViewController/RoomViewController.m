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
#import <MobileCoreServices/MobileCoreServices.h>

#import <MediaPlayer/MediaPlayer.h>

#import "RoomViewController.h"
#import "MemberViewController.h"
#import "RoomMessage.h"
#import "RoomMessageTableCell.h"
#import "RoomMemberTableCell.h"
#import "RoomTitleView.h"

#import "MatrixSDKHandler.h"
#import "AppDelegate.h"
#import "AppSettings.h"

#import "MediaManager.h"
#import "MXCTools.h"

#import "MXCGrowingTextView.h"

#define ROOMVIEWCONTROLLER_TYPING_TIMEOUT_SEC 10

#define ROOMVIEWCONTROLLER_UPLOAD_FILE_SIZE 5000000

#define ROOMVIEWCONTROLLER_BACK_PAGINATION_SIZE 20
#define ROOMVIEWCONTROLLER_BACK_PAGINATION_MAX_SCROLLING_OFFSET 100

#define ROOM_MESSAGE_CELL_DEFAULT_HEIGHT 50
#define ROOM_MESSAGE_CELL_DEFAULT_TEXTVIEW_TOP_CONST 10
#define ROOM_MESSAGE_CELL_DEFAULT_ATTACHMENTVIEW_TOP_CONST 18
#define ROOM_MESSAGE_CELL_HEIGHT_REDUCTION_WHEN_SENDER_INFO_IS_HIDDEN -10

#define ROOM_MESSAGE_CELL_TEXTVIEW_LEADING_AND_TRAILING_CONSTRAINT_TO_SUPERVIEW 120 // (51 + 69)

#define HIDDEN_UNSENT_MSG_LABEL 12012015

NSString *const kCmdChangeDisplayName = @"/nick";
NSString *const kCmdEmote = @"/me";
NSString *const kCmdJoinRoom = @"/join";
NSString *const kCmdKickUser = @"/kick";
NSString *const kCmdBanUser = @"/ban";
NSString *const kCmdUnbanUser = @"/unban";
NSString *const kCmdSetUserPowerLevel = @"/op";
NSString *const kCmdResetUserPowerLevel = @"/deop";


@interface RoomViewController () {
    BOOL forceScrollToBottomOnViewDidAppear;
    BOOL isJoinRequestInProgress;
    
    // Typing notification
    NSDate *lastTypingDate;
    NSTimer* typingTimer;
    id typingNotifListener;
    NSArray *currentTypingUsers;
    
    // Back pagination
    BOOL isBackPaginationInProgress;
    BOOL isFirstPagination;
    NSUInteger backPaginationAddedMsgNb;
    NSUInteger backPaginationHandledEventsNb;
    NSOperation *backPaginationOperation;
    CGFloat backPaginationSavedFirstMsgHeight;
    
    // Members list
    NSArray *members;
    id membersListener;
    
    // Attachment handling
    MXCImageView *highResImageView;
    NSString *AVAudioSessionCategory;
    MPMoviePlayerController *videoPlayer;
    MPMoviePlayerController *tmpVideoPlayer;
    NSString *selectedVideoURL;
    NSString *selectedVideoCachePath;
    
    // used to trap the slide to close the keyboard
    UIView* inputAccessoryView;
    BOOL isKeyboardObserver;
    BOOL isKeyboardDisplayed;
    CGFloat keyboardHeight;
    
    // default contraint values
    CGFloat defaultMessagesTableViewBottomConstraint;
    CGFloat defaultControlViewBottomConstraint;
    
    // save the last edited text
    // do not send unexpected typing events
    // HPGrowingTextView triggers growingTextViewDidChange event when it recomposes itself
    NSString* lastEditedText;
    
    // Date formatter (nil if dateTime info is hidden)
    NSDateFormatter *dateFormatter;
    
    // Local echo
    NSMutableArray *pendingOutgoingEvents;
    NSMutableArray *tmpCachedAttachments;
    
    // the user taps on a member thumbnail
    MXRoomMember *selectedRoomMember;
}

@property (weak, nonatomic) IBOutlet UINavigationItem *roomNavItem;
@property (weak, nonatomic) IBOutlet RoomTitleView *roomTitleView;
@property (weak, nonatomic) IBOutlet UITableView *messagesTableView;
@property (weak, nonatomic) IBOutlet UIView *controlView;
@property (weak, nonatomic) IBOutlet UIButton *optionBtn;
@property (weak, nonatomic) IBOutlet MXCGrowingTextView *messageTextView;
@property (weak, nonatomic) IBOutlet UIButton *sendBtn;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *messagesTableViewBottomConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *controlViewBottomConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *controlViewHeightConstraint;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *activityIndicator;
@property (weak, nonatomic) IBOutlet UIView *membersView;
@property (weak, nonatomic) IBOutlet UITableView *membersTableView;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *membersListButtonItem;

@property (strong, nonatomic) MXRoom *mxRoom;
@property (strong, nonatomic) MXCAlert *actionMenu;
@property (strong, nonatomic) MXCImageView* imageValidationView;

// Messages
@property (strong, nonatomic)NSMutableArray *messages;
@property (strong, nonatomic)id messagesListener;
@property (strong, nonatomic)id redactionListener;
@end

@implementation RoomViewController
@synthesize messages;

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    forceScrollToBottomOnViewDidAppear = YES;
    // Hide messages table by default in order to hide initial scrolling to the bottom
    self.messagesTableView.hidden = YES;
    
    // Add tap detection on members view in order to hide members when the user taps outside members list
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideRoomMembers)];
    [tap setNumberOfTouchesRequired:1];
    [tap setNumberOfTapsRequired:1];
    [tap setDelegate:self];
    [self.membersView addGestureRecognizer:tap];
    
    isKeyboardObserver = NO;
    
    _sendBtn.enabled = NO;
    _sendBtn.alpha = 0.5;
    
    pendingOutgoingEvents = [NSMutableArray array];
    
    // add an input to check if the keyboard is hiding with sliding it
    inputAccessoryView = [[UIView alloc] initWithFrame:CGRectZero];
    self.messageTextView.internalTextView.inputAccessoryView = inputAccessoryView;
    
    // ensure that the titleView will be scaled when it will be required
    // during a screen rotation for example.
    self.roomTitleView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    // default contraint values
    defaultMessagesTableViewBottomConstraint = _messagesTableViewBottomConstraint.constant;
    defaultControlViewBottomConstraint = _controlViewBottomConstraint.constant;
    
    // draw a rounded border around the textView
    self.messageTextView.layer.cornerRadius = 5;
    self.messageTextView.layer.borderWidth = 1;
    self.messageTextView.layer.borderColor = [UIColor lightGrayColor].CGColor;
    self.messageTextView.clipsToBounds = YES;
    self.messageTextView.backgroundColor = [UIColor whiteColor];
    // on IOS 8, the growing textview animation could trigger weird UI animations
    // indeed, the messages tableView can be refreshed while its height is updated (e.g. when setting a message)
    self.messageTextView.animateHeightChange = NO;
    lastEditedText = self.messageTextView.text;
}

- (void)dealloc {
    lastTypingDate = nil;
    [typingTimer invalidate];
    typingTimer = nil;
    if (typingNotifListener) {
        [self.mxRoom removeListener:typingNotifListener];
        typingNotifListener = nil;
    }
    currentTypingUsers = nil;
    
    // Release local echo resources
    pendingOutgoingEvents = nil;
    NSUInteger index = tmpCachedAttachments.count;
    NSError *error = nil;
    while (index--) {
        if (![[NSFileManager defaultManager] removeItemAtPath:[tmpCachedAttachments objectAtIndex:index] error:&error]) {
            NSLog(@"Fail to delete cached media: %@", error);
        }
    }
    tmpCachedAttachments = nil;
    
    [self hideAttachmentView];
    
    messages = nil;
    if (_messagesListener) {
        [self.mxRoom removeListener:_messagesListener];
        _messagesListener = nil;
        [self.mxRoom removeListener:_redactionListener];
        _redactionListener = nil;
        [[AppSettings sharedSettings] removeObserver:self forKeyPath:@"hideRedactedInformation"];
        [[AppSettings sharedSettings] removeObserver:self forKeyPath:@"hideUnsupportedEvents"];
        [[MatrixSDKHandler sharedHandler] removeObserver:self forKeyPath:@"status"];
        [[MatrixSDKHandler sharedHandler] removeObserver:self forKeyPath:@"isResumeDone"];
    }
    self.mxRoom = nil;
    
    if (backPaginationOperation) {
        [backPaginationOperation cancel];
        backPaginationOperation = nil;
    }
    
    members = nil;
    if (membersListener) {
        membersListener = nil;
    }
    
    if (self.actionMenu) {
        [self.actionMenu dismiss:NO];
        self.actionMenu = nil;
    }
    
    if (dateFormatter) {
        dateFormatter = nil;
    }
    
    if (_messageTextView) {
        
        _messageTextView.internalTextView.inputAccessoryView = inputAccessoryView = nil;
        _messageTextView.delegate = nil;
        _messageTextView = nil;
    }
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    if (isBackPaginationInProgress || isJoinRequestInProgress) {
        // Busy - be sure that activity indicator is running
        [self startActivityIndicator];
    }
    
    // Register a listener for events that concern room members
    MatrixSDKHandler *mxHandler = [MatrixSDKHandler sharedHandler];
    NSArray *mxMembersEvents = @[
                                 kMXEventTypeStringRoomMember,
                                 kMXEventTypeStringRoomPowerLevels,
                                 kMXEventTypeStringPresence
                                 ];
    membersListener = [mxHandler.mxSession listenToEventsOfTypes:mxMembersEvents onEvent:^(MXEvent *event, MXEventDirection direction, id customObject) {
        // consider only live event
        if (direction == MXEventDirectionForwards) {
            // Check the room Id (if any)
            if (event.roomId && [event.roomId isEqualToString:self.roomId] == NO) {
                // This event does not concern the current room members
                return;
            }
            
            // Check whether no text field is editing before refreshing title view
            if (!self.roomTitleView.isEditing) {
                [self.roomTitleView refreshDisplay];
            }

            // refresh the
            if (members.count > 0) {
                // Hide potential action sheet
                if (self.actionMenu) {
                    [self.actionMenu dismiss:NO];
                    self.actionMenu = nil;
                }
                // Refresh members list
                [self updateRoomMembers];
                [self.membersTableView reloadData];
            }
        }
    }];
    
    self.messageTextView.delegate = self;

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onKeyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onKeyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppDidEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    // hide action
    if (self.actionMenu) {
        [self.actionMenu dismiss:NO];
        self.actionMenu = nil;
    }
    
    // Hide members by default
    [self hideRoomMembers];
    
    self.messageTextView.delegate = nil;

    // slide to hide keyboard management
    if (isKeyboardObserver) {
        [inputAccessoryView.superview removeObserver:self forKeyPath:@"frame"];
        [inputAccessoryView.superview removeObserver:self forKeyPath:@"center"];
        isKeyboardObserver = NO;
    }
    
    [self dismissAttachmentImageViews];
    
    if (membersListener) {
        MatrixSDKHandler *mxHandler = [MatrixSDKHandler sharedHandler];
        [mxHandler.mxSession removeListener:membersListener];
        membersListener = nil;
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    // Set visible room id
    [AppDelegate theDelegate].masterTabBarController.visibleRoomId = self.roomId;
    
    if (forceScrollToBottomOnViewDidAppear) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Scroll to the bottom
            [self scrollToBottomAnimated:animated];
        });
        forceScrollToBottomOnViewDidAppear = NO;
        self.messagesTableView.hidden = NO;
    }

    [self updateUI];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    
    // Reset visible room id
    [AppDelegate theDelegate].masterTabBarController.visibleRoomId = nil;
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id <UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(coordinator.transitionDuration * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!isKeyboardDisplayed) {
            [self updateMessageTextViewFrame];
        }
        // Cell width will be updated, force table refresh to take into account changes of message components
        [self.messagesTableView reloadData];
    });
}

// The 2 following methods are deprecated since iOS 8
- (void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    [super willRotateToInterfaceOrientation:toInterfaceOrientation duration:duration];
    
    // Cell width will be updated, force table refresh to take into account changes of message components
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.messagesTableView reloadData];
    });
}
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    
    if (!isKeyboardDisplayed) {
        [self updateMessageTextViewFrame];
    }
}

- (void)onAppDidEnterBackground {
    [self dismissAttachmentImageViews];
}

- (void)updateUI {
    // Check whether a room is selected to show/hide UI items
    if (self.mxRoom) {
        self.controlView.hidden = NO;
        // Check room members to enable/disable members button in nav bar
        self.membersListButtonItem.enabled = ([self.mxRoom.state members].count != 0);
    } else {
        self.controlView.hidden = YES;
        self.membersListButtonItem.enabled = NO;
        _activityIndicator.hidden = YES;
    }
    [self.roomTitleView refreshDisplay];
}

- (void)addPictureViewTapGesture:(RoomMessageTableCell*)cell {
    if (!cell.pictureView.hidden) {
        UITapGestureRecognizer* tapGesture = nil;

        // check if it is already defined
        // gesture in storyboard does not seem to work properly
        // it always triggers a tap event on the first cell
        for (UIGestureRecognizer* gesture in cell.pictureView.gestureRecognizers) {
            
            if ([gesture isKindOfClass:[UITapGestureRecognizer class]]) {
                tapGesture = (UITapGestureRecognizer*)gesture;
                break;
            }
        }
        
        // add it if it is not yet defined
        if (!tapGesture) {
            tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onContactThumbnailTap:)];
            [tapGesture setNumberOfTouchesRequired:1];
            [tapGesture setNumberOfTapsRequired:1];
            [tapGesture setDelegate:self];
            [cell.pictureView addGestureRecognizer:tapGesture];
            cell.pictureView.userInteractionEnabled = YES;

            // ensure that nothing will hide this view
            [cell.pictureView.superview bringSubviewToFront:cell.pictureView];
        }
    }
}

#pragma mark -

- (void)setRoomId:(NSString *)roomId {
    if ([self.roomId isEqualToString:roomId] == NO) {
        _roomId = roomId;
        [self forceRefresh];
    }
}

- (void)forceRefresh {
    // Reload room data here
    [self configureView];
    // Update UI
    [self updateUI];
}

#pragma mark - UIGestureRecognizer delegate

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.view == self.membersView) {
        // Compute actual frame of the displayed members list
        CGRect frame = self.membersTableView.frame;
        if (self.membersTableView.tableFooterView.frame.origin.y < frame.size.height) {
            frame.size.height = self.membersTableView.tableFooterView.frame.origin.y;
        }
        // gestureRecognizer should begin only if tap is outside members list
        return !CGRectContainsPoint(frame, [gestureRecognizer locationInView:self.membersView]);
    }
    return YES;
}

- (IBAction)onProgressLongTap:(UILongPressGestureRecognizer*)sender {
    if (sender.state == UIGestureRecognizerStateBegan) {
        // find out the linked uitableviewcell
        UIView* view = sender.view;
        
        while(view && ![view isKindOfClass:[UITableViewCell class]]) {
            view = view.superview;
        }
        
        // if it is a RoomMessageTableCell
        if ([view isKindOfClass:[RoomMessageTableCell class]]) {
            __weak typeof(self) weakSelf = self;
            
            NSString* url = ((RoomMessageTableCell*)view).message.attachmentURL;
            MediaLoader *loader = [MediaManager existingDownloaderForURL:url inFolder:self.roomId];
            
            // offer to cancel a download only if there is a pending one
            if (loader) {
                self.actionMenu = [[MXCAlert alloc] initWithTitle:nil message:@"Cancel the download ?" style:MXCAlertStyleAlert];
                self.actionMenu.cancelButtonIndex = [self.actionMenu addActionWithTitle:@"Cancel" style:MXCAlertActionStyleDefault handler:^(MXCAlert *alert) {
                    weakSelf.actionMenu = nil;
                }];
                self.actionMenu.cancelButtonIndex = [self.actionMenu addActionWithTitle:@"OK" style:MXCAlertActionStyleDefault handler:^(MXCAlert *alert) {
                    
                    // get again the loader, the cell could have been reused.
                    MediaLoader *loader = [MediaManager existingDownloaderForURL:url inFolder:weakSelf.roomId];
                    if (loader) {
                        [loader cancel];
                    }

                    weakSelf.actionMenu = nil;
                }];
                
                [self.actionMenu showInViewController:self];
            }
        }
    }
}
- (IBAction)onContactThumbnailTap:(UITapGestureRecognizer*)sender {
    UIView* view = sender.view;
    
    while (view && ![view isKindOfClass:[RoomMessageTableCell class]]) {
        view = view.superview;
    }
    
    if ([view isKindOfClass:[RoomMessageTableCell class]]) {
        NSIndexPath *indexPath = [self.messagesTableView indexPathForCell:(RoomMessageTableCell*)view];
        RoomMessage* message = nil;
        
        @synchronized(self) {
            if (indexPath.row < messages.count) {
                message = [messages objectAtIndex:indexPath.row];
            }
        }
        
        if (message) {
            selectedRoomMember = [self.mxRoom.state memberWithUserId:message.senderId];
        
            if (selectedRoomMember) {
                [self performSegueWithIdentifier:@"showMemberSheet" sender:self];
            }
        }
    }
}

#pragma mark - Internal methods

- (void)configureView {
    // Check whether a request is in progress to join the room
    if (isJoinRequestInProgress) {
        // Busy - be sure that activity indicator is running
        [self startActivityIndicator];
        return;
    }
    
    if (self.mxRoom) {
        // Remove potential listener
        if (_messagesListener){
            [self.mxRoom removeListener:_messagesListener];
            _messagesListener = nil;
            [self.mxRoom removeListener:_redactionListener];
            _redactionListener = nil;
            [[AppSettings sharedSettings] removeObserver:self forKeyPath:@"hideRedactedInformation"];
            [[AppSettings sharedSettings] removeObserver:self forKeyPath:@"hideUnsupportedEvents"];
            [[MatrixSDKHandler sharedHandler] removeObserver:self forKeyPath:@"status"];
            [[MatrixSDKHandler sharedHandler] removeObserver:self forKeyPath:@"isResumeDone"];
        }
        currentTypingUsers = nil;
        if (typingNotifListener) {
            [self.mxRoom removeListener:typingNotifListener];
        }
    }
    // The whole room history is flushed here to rebuild it from the current instant (live)
    @synchronized(self) {
        messages = nil;
    }
    
    // Disable room title edition
    self.roomTitleView.editable = NO;
    
    // Update room data
    MatrixSDKHandler *mxHandler = [MatrixSDKHandler sharedHandler];
    self.mxRoom = nil;
    if (self.roomId) {
        self.mxRoom = [mxHandler.mxSession roomWithRoomId:self.roomId];
    }
    if (self.mxRoom) {
        // Check first whether we have to join the room
        if (self.mxRoom.state.membership == MXMembershipInvite) {
            isJoinRequestInProgress = YES;
            [self startActivityIndicator];
            [self.mxRoom join:^{
                [self stopActivityIndicator];
                isJoinRequestInProgress = NO;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self configureView];
                });
            } failure:^(NSError *error) {
                [self stopActivityIndicator];
                isJoinRequestInProgress = NO;
                NSLog(@"Failed to join room (%@): %@", self.mxRoom.state.displayname, error);
                //Alert user
                [[AppDelegate theDelegate] showErrorAsAlert:error];
            }];
            return;
        }
        
        // Enable room title edition
        self.roomTitleView.editable = YES;
        
        @synchronized(self) {
            messages = [NSMutableArray array];
        }
        
        [[AppSettings sharedSettings] addObserver:self forKeyPath:@"hideRedactedInformation" options:0 context:nil];
        [[AppSettings sharedSettings] addObserver:self forKeyPath:@"hideUnsupportedEvents" options:0 context:nil];
        [mxHandler addObserver:self forKeyPath:@"status" options:0 context:nil];
        [mxHandler addObserver:self forKeyPath:@"isResumeDone" options:0 context:nil];
        // Register a listener to handle messages
        _messagesListener = [self.mxRoom listenToEventsOfTypes:mxHandler.eventsFilterForMessages onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
            // Handle first live events
            if (direction == MXEventDirectionForwards) {
                // Check user's membership in live room state (Indeed we have to go back on recents when user leaves, or is kicked/banned)
                if (self.mxRoom.state.membership == MXMembershipLeave || self.mxRoom.state.membership == MXMembershipBan) {
                    [[AppDelegate theDelegate].masterTabBarController popRoomViewControllerAnimated:NO];
                    return;
                }
                
                // Update Table on processing queue
                MXRoomState *roomStateCpy = [roomState copy];
                dispatch_async(mxHandler.processingQueue, ^{
                    BOOL isHandled = NO;
                    
                    // For outgoing message, we update here local echo data
                    if ([event.userId isEqualToString:mxHandler.userId] && messages.count) {
                        RoomMessage *message = nil;
                        // Consider first the last message
                        @synchronized(self) {
                            message = [messages lastObject];
                        }
                        
                        if ([message containsEventId:event.eventId]) {
                            // The handling of this outgoing message is complete. We remove here its local echo
                            if (message.messageType == RoomMessageTypeText) {
                                [message removeEvent:event.eventId];
                                // Update message with the actual outgoing event
                                isHandled = [message addEvent:event withRoomState:roomStateCpy];
                                if (!message.components.count) {
                                    [self removeMessage:message];
                                }
                            } else {
                                // Create a new message to handle attachment
                                RoomMessage *aNewMessage = [[RoomMessage alloc] initWithEvent:event andRoomState:roomStateCpy];
                                if (aNewMessage) {
                                    [self replaceMessage:message withMessage:aNewMessage];
                                } else {
                                    // Ignore unsupported/unexpected events
                                    [self removeMessage:message];
                                }
                                isHandled = YES;
                            }
                        } else {
                            // Look for the event id in other messages
                            message = [self messageWithEventId:event.eventId];
                            if (message) {
                                // The handling of this outgoing message is complete. We remove here its local echo
                                if (message.messageType == RoomMessageTypeText) {
                                    [message removeEvent:event.eventId];
                                    if (!message.components.count) {
                                        [self removeMessage:message];
                                    }
                                } else {
                                    [self removeMessage:message];
                                }
                            } else {
                                // Here the received event id has not been found in current messages list.
                                // This may happen in 2 cases:
                                // - the message has been posted from another device.
                                // - the message is received from events stream whereas the app is waiting for our PUT to return (see pendingOutgoingEvents).
                                // In this second case, the pending event is replaced here (No additional action is required when PUT will return).
                                MXEvent *pendingEvent = [self pendingEventRelatedToEvent:event];
                                if (pendingEvent) {
                                    // Remove this event from the pending list
                                    @synchronized(self) {
                                        [pendingOutgoingEvents removeObject:pendingEvent];
                                    }
                                    // Remove this local event from messages
                                    message = [self messageWithEventId:pendingEvent.eventId];
                                    if (message) {
                                        if (message.messageType == RoomMessageTypeText) {
                                            [message removeEvent:pendingEvent.eventId];
                                            if (!message.components.count) {
                                                [self removeMessage:message];
                                            }
                                        } else {
                                            [self removeMessage:message];
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    if (isHandled == NO) {
                        // Check whether the event may be grouped with last message
                        RoomMessage *lastMessage = nil;
                        @synchronized(self) {
                            lastMessage = [messages lastObject];
                        }
                        
                        if (lastMessage && [lastMessage addEvent:event withRoomState:roomStateCpy]) {
                            isHandled = YES;
                        } else {
                            // Create a new item
                            lastMessage = [[RoomMessage alloc] initWithEvent:event andRoomState:roomStateCpy];
                            if (lastMessage) {
                                @synchronized(self) {
                                    [messages addObject:lastMessage];
                                }
                                isHandled = YES;
                            } // else ignore unsupported/unexpected events
                        }
                    }
                    
                    // Refresh table display except if a back pagination is in progress
                    if (!isBackPaginationInProgress) {
                        // We will scroll to bottom after updating tableView only if the most recent message is entirely visible.
                        CGFloat maxPositionY = self.messagesTableView.contentOffset.y + (self.messagesTableView.frame.size.height - self.messagesTableView.contentInset.bottom);
                        // Be a bit less retrictive, scroll even if the most recent message is partially hidden
                        maxPositionY += 30;
                        BOOL shouldScrollToBottom = (maxPositionY >= self.messagesTableView.contentSize.height);
                        // Refresh tableView
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self.messagesTableView reloadData];
                            if (shouldScrollToBottom) {
                                [self scrollToBottomAnimated:YES];
                            }
                        });
                        
                        if (isHandled) {
                            if ([[AppDelegate theDelegate].masterTabBarController.visibleRoomId isEqualToString:self.roomId] == NO) {
                                // Some new events are received for this room while it is not visible, scroll to bottom on viewDidAppear to focus on them
                                forceScrollToBottomOnViewDidAppear = YES;
                            }
                        }
                    }
                });
            } else if (isBackPaginationInProgress && direction == MXEventDirectionBackwards) {
                // Back pagination is in progress, we add an old event at the beginning of messages (on processing queue)
                MXRoomState *roomStateCpy = [roomState copy];
                dispatch_async(mxHandler.processingQueue, ^{
                    RoomMessage *firstMessage;
                    @synchronized(self) {
                        firstMessage = [messages firstObject];
                    }
                    if (!firstMessage || [firstMessage addEvent:event withRoomState:roomStateCpy] == NO) {
                        firstMessage = [[RoomMessage alloc] initWithEvent:event andRoomState:roomStateCpy];
                        if (firstMessage) {
                            @synchronized(self) {
                                [messages insertObject:firstMessage atIndex:0];
                            }
                            backPaginationAddedMsgNb ++;
                            backPaginationHandledEventsNb ++;
                        }
                        // Ignore unsupported/unexpected events
                    } else {
                        backPaginationHandledEventsNb ++;
                    }
                    
                    // Display is refreshed at the end of back pagination (see onComplete block)
                });
            }
        }];
        
        // Register a listener to handle redaction in live stream
        _redactionListener = [self.mxRoom listenToEventsOfTypes:@[kMXEventTypeStringRoomRedaction] onEvent:^(MXEvent *redactionEvent, MXEventDirection direction, MXRoomState *roomState) {
            // Consider only live redaction events
            if (direction == MXEventDirectionForwards) {
                // Update Table on processing queue
                dispatch_async(mxHandler.processingQueue, ^{
                    // Check whether a message contains the redacted event
                    RoomMessage *message = [self messageWithEventId:redactionEvent.redacts];
                    if (message) {
                        // Retrieve the original to redact it
                        MXEvent *originalEvent = [message componentWithEventId:redactionEvent.redacts].event;
                        MXEvent *redactedEvent = [originalEvent prune];
                        redactedEvent.redactedBecause = redactionEvent.originalDictionary;
                        
                        if (redactedEvent.isState) {
                            // FIXME: The room state must be refreshed here since this redacted event.
                            NSLog(@"CAUTION: a state event has been redacted, room state may not be up to date");
                        }
                        
                        // We replace the event with the redacted one
                        [message updateRedactedEvent:redactedEvent];
                        if (!message.components.count) {
                            [self removeMessage:message];
                        }
                    }
                    
                    // Refresh table display except if a back pagination is in progress
                    if (!isBackPaginationInProgress) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self.messagesTableView reloadData];
                        });
                    }
                });
            }
        }];
        
        // Add typing notification listener
        typingNotifListener = [self.mxRoom listenToEventsOfTypes:@[kMXEventTypeStringTypingNotification] onEvent:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
            // Handle only live events
            if (direction == MXEventDirectionForwards) {
                // Switch on the processing queue in order to serialize this operation with messages handling
                dispatch_async(mxHandler.processingQueue, ^{
                    // Retrieve typing users list
                    NSMutableArray *typingUsers = [NSMutableArray arrayWithArray:self.mxRoom.typingUsers];
                    // Remove typing info for the current user
                    NSUInteger index = [typingUsers indexOfObject:mxHandler.userId];
                    if (index != NSNotFound) {
                        [typingUsers removeObjectAtIndex:index];
                    }
                    // Ignore this notification if both arrays are empty
                    if (currentTypingUsers.count || typingUsers.count) {
                        currentTypingUsers = typingUsers;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self.messagesTableView reloadData];
                            if (members) {
                                [self.membersTableView reloadData];
                            }
                        });
                    }
                });
            }
        }];
        currentTypingUsers = self.mxRoom.typingUsers;
        
        // Trigger a back pagination by reseting first backState to get room history from live
        [self.mxRoom resetBackState];
        [self triggerBackPagination];
    }
    
    self.roomTitleView.mxRoom = self.mxRoom;
    
    [self.messagesTableView reloadData];
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    // Scroll table view to the bottom
    NSInteger rowNb = messages.count;
    // Check whether there is some data and whether the table has already been loaded
    if (rowNb && self.messagesTableView.contentSize.height) {
        [self.messagesTableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(rowNb - 1) inSection:0] atScrollPosition:UITableViewScrollPositionBottom animated:animated];
    }
}

- (void)startActivityIndicator {
    [_activityIndicator startAnimating];
}

- (void)stopActivityIndicator {
    // Check whether all conditions are satisfied before stopping loading wheel
    MatrixSDKHandler *mxHandler = [MatrixSDKHandler sharedHandler];
    if (mxHandler.status == MatrixSDKHandlerStatusServerSyncDone && mxHandler.isResumeDone && !isBackPaginationInProgress && !isJoinRequestInProgress) {
        [_activityIndicator stopAnimating];
    }
}

- (void)updateMessageTextViewFrame {
    if (!isKeyboardDisplayed) {
        // compute the visible area (tableview + text input)
        // the tableview must use at least 50 pixels to let the user hides the keybaord
        CGFloat maxTextHeight = (self.view.frame.size.height - self.navigationController.navigationBar.frame.size.height - [AppDelegate theDelegate].masterTabBarController.tabBar.frame.size.height - MIN([UIApplication sharedApplication].statusBarFrame.size.height, [UIApplication sharedApplication].statusBarFrame.size.width)) - 50;
        
        _messageTextView.maxHeight = maxTextHeight;
        [_messageTextView refreshHeight];
    }
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([@"status" isEqualToString:keyPath]) {
        if ([MatrixSDKHandler sharedHandler].status == MatrixSDKHandlerStatusServerSyncDone) {
            [self stopActivityIndicator];
        } else {
            [self startActivityIndicator];
        }
    } else if ([@"isResumeDone" isEqualToString:keyPath]) {
        if ([[MatrixSDKHandler sharedHandler] isResumeDone]) {
            [self stopActivityIndicator];
        } else {
            [self startActivityIndicator];
        }
    } else if ((object == inputAccessoryView.superview) && ([@"frame" isEqualToString:keyPath] || [@"center" isEqualToString:keyPath])) {
        
        // if the keyboard is displayed, check if the keyboard is hiding with a slide animation
        if (inputAccessoryView && inputAccessoryView.superview) {
            UIEdgeInsets insets = self.messagesTableView.contentInset;
        
            CGSize screenSize = [[UIScreen mainScreen] bounds].size;
            
            // on IOS 8, the screen size is oriented
            if ((NSFoundationVersionNumber <= NSFoundationVersionNumber_iOS_7_1) && UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation)) {
                screenSize = CGSizeMake(screenSize.height, screenSize.width);
            }
            
            keyboardHeight = screenSize.height - inputAccessoryView.superview.frame.origin.y;
            
            insets.bottom = keyboardHeight + self.controlView.frame.size.height - defaultMessagesTableViewBottomConstraint;
            
            // Move the control view
            // Don't forget the offset related to tabBar
            CGFloat newConstant = keyboardHeight - [AppDelegate theDelegate].masterTabBarController.tabBar.frame.size.height;
            
            // draw over the bound
            if ((_controlViewBottomConstraint.constant < 0) || (insets.bottom < self.controlView.frame.size.height)) {
                newConstant = 0;
                insets.bottom = self.controlView.frame.size.height;
            }
            else {
                // IOS 8 / landscape issue
                // when the top of the keyboard reaches the top of the tabbar, it triggers UIKeyboardWillShowNotification events in loop
                [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
            }
            // update the table the tableview height
            self.messagesTableView.contentInset = insets;
            _controlViewBottomConstraint.constant = newConstant;
        }
    } else if ([@"hideUnsupportedEvents" isEqualToString:keyPath] || [@"hideRedactedInformation" isEqualToString:keyPath]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self configureView];
        });
    }
}

#pragma mark - Message handling

// Return the message (if any) which contains the provided event id in its components
- (RoomMessage*)messageWithEventId:(NSString *)eventId {
    RoomMessage *message = nil;
    @synchronized(self) {
        NSUInteger index = messages.count;
        while (index--) {
            message = [messages objectAtIndex:index];
            if ([message containsEventId:eventId]) {
                break;
            }
            message = nil;
        }
    }
    return message;
}

- (void)removeMessage:(RoomMessage*)message {
    RoomMessage *previousMessage = nil;
    RoomMessage *nextMessage = nil;
    @synchronized(self) {
        NSUInteger index = [messages indexOfObject:message];
        if (index != NSNotFound) {
            [messages removeObjectAtIndex:index];
            
            // Retrieve adjoined messages if the message was neither the first nor the last one
            if (index && index < messages.count) {
                previousMessage = [messages objectAtIndex:index - 1];
                nextMessage = [messages objectAtIndex:index];
            }
        }
    }
    
    if (previousMessage && nextMessage) {
        // Check whether both messages can merge
        if ([previousMessage mergeWithRoomMessage:nextMessage]) {
            [self removeMessage:nextMessage];
        }
    }
}

- (void)replaceMessage:(RoomMessage*)message withMessage:(RoomMessage*)aNewMessage {
    @synchronized(self) {
        NSUInteger index = [messages indexOfObject:message];
        if (index != NSNotFound) {
            [messages replaceObjectAtIndex:index withObject:aNewMessage];
        }
    }
}

#pragma mark - Back pagination

- (void)triggerBackPagination {
    // Check whether a back pagination is already in progress
    if (isBackPaginationInProgress) {
        return;
    }
    
    if (self.mxRoom.canPaginate) {
        NSUInteger requestedItemsNb = ROOMVIEWCONTROLLER_BACK_PAGINATION_SIZE;
        // In case of first pagination, we will request only messages from the store to speed up the room display
        if (!messages.count) {
            isFirstPagination = YES;
            requestedItemsNb = self.mxRoom.remainingMessagesForPaginationInStore;
            if (!requestedItemsNb || ROOMVIEWCONTROLLER_BACK_PAGINATION_SIZE < requestedItemsNb) {
                requestedItemsNb = ROOMVIEWCONTROLLER_BACK_PAGINATION_SIZE;
            }
        }
        
        [self startActivityIndicator];
        isBackPaginationInProgress = YES;
        backPaginationAddedMsgNb = 0;
        // Store the current height of the first message (if any)
        backPaginationSavedFirstMsgHeight = 0;
        if (messages.count) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:0];
            backPaginationSavedFirstMsgHeight = [self tableView:self.messagesTableView heightForRowAtIndexPath:indexPath];
        }
        
        dispatch_async([MatrixSDKHandler sharedHandler].processingQueue, ^{
            [self paginateBackMessages:requestedItemsNb];
        });
    }
}

- (void)paginateBackMessages:(NSUInteger)requestedItemsNb {
    backPaginationHandledEventsNb = 0;
    backPaginationOperation = [self.mxRoom paginateBackMessages:requestedItemsNb complete:^{
        // Sanity check: check whether the view controller has not been released while back pagination was running
        if (self.roomId == nil) {
            return;
        }
        
        // Check whether we received less items than expected, and check condition to be able to ask more.
        // This operation must be done on processing queue to be sync with the events reception
        dispatch_async([MatrixSDKHandler sharedHandler].processingQueue, ^{
            BOOL shouldLoop = ((backPaginationHandledEventsNb < requestedItemsNb) && self.mxRoom.canPaginate);
            if (shouldLoop) {
                NSUInteger missingItemsNb = requestedItemsNb - backPaginationHandledEventsNb;
                // About first pagination, we will loop only if the store has more items (except if none item has been handled, in this case loop is required)
                if (isFirstPagination && backPaginationHandledEventsNb) {
                    if (self.mxRoom.remainingMessagesForPaginationInStore < missingItemsNb) {
                        missingItemsNb = self.mxRoom.remainingMessagesForPaginationInStore;
                    }
                }
                
                if (missingItemsNb) {
                    // Ask more items
                    [self paginateBackMessages:missingItemsNb];
                    return;
                }
            }
            
            // Here we are done
            [self onBackPaginationComplete];
        });
    } failure:^(NSError *error) {
        NSLog(@"Failed to paginate back: %@", error);
        dispatch_async([MatrixSDKHandler sharedHandler].processingQueue, ^{
            [self onBackPaginationComplete];
        });
        //Alert user
        [[AppDelegate theDelegate] showErrorAsAlert:error];
    }];
}

- (void)onBackPaginationComplete {
    // Reset
    isFirstPagination = NO;
    backPaginationOperation = nil;
    
    // We scroll to bottom when table is loaded for the first time
    BOOL shouldScrollToBottom = (self.messagesTableView.contentSize.height == 0);
    if (!shouldScrollToBottom) {
        // We will scroll to bottom if the displayed content does not reach the bottom (after adding back pagination)
        CGFloat maxPositionY = self.messagesTableView.contentOffset.y + (self.messagesTableView.frame.size.height - self.messagesTableView.contentInset.bottom);
        // Compute the height of the blank part at the bottom
        if (maxPositionY > self.messagesTableView.contentSize.height) {
            CGFloat blankAreaHeight = maxPositionY - self.messagesTableView.contentSize.height;
            // Scroll to bottom if this blank area is greater than max scrolling offet
            shouldScrollToBottom = (blankAreaHeight >= ROOMVIEWCONTROLLER_BACK_PAGINATION_MAX_SCROLLING_OFFSET);
        }
    }
    
    CGFloat verticalOffset = 0;
    if (shouldScrollToBottom == NO) {
        // In this case, we will adjust the vertical offset in order to make visible only a few part of added messages (at the top of the table)
        NSIndexPath *indexPath;
        // Compute the cumulative height of the added messages
        for (NSUInteger index = 0; index < backPaginationAddedMsgNb; index++) {
            indexPath = [NSIndexPath indexPathForRow:index inSection:0];
            verticalOffset += [self tableView:self.messagesTableView heightForRowAtIndexPath:indexPath];
        }
        // Add delta of the height of the first existing message
        if (messages.count > backPaginationAddedMsgNb) {
            indexPath = [NSIndexPath indexPathForRow:backPaginationAddedMsgNb inSection:0];
            verticalOffset += ([self tableView:self.messagesTableView heightForRowAtIndexPath:indexPath] - backPaginationSavedFirstMsgHeight);
        }
        // Deduce the vertical offset from this height
        verticalOffset -= ROOMVIEWCONTROLLER_BACK_PAGINATION_MAX_SCROLLING_OFFSET;
    }
    // Reset count to enable tableView update
    backPaginationAddedMsgNb = 0;
    
    // Return on main thread to end back pagination
    dispatch_async(dispatch_get_main_queue(), ^{
        // Reload table
        [self.messagesTableView reloadData];
        
        // Adjust vertical content offset
        if (shouldScrollToBottom) {
            [self scrollToBottomAnimated:NO];
        } else if (verticalOffset > 0) {
            // Adjust vertical offset in order to limit scrolling down
            CGPoint contentOffset = self.messagesTableView.contentOffset;
            contentOffset.y = verticalOffset - self.messagesTableView.contentInset.top;
            [self.messagesTableView setContentOffset:contentOffset animated:NO];
        }
        isBackPaginationInProgress = NO;
        [self stopActivityIndicator];
    });
}

# pragma mark - Room members

- (void)updateRoomMembers {
    NSArray* membersList = [self.mxRoom.state members];
    
    if (![[AppSettings sharedSettings] displayLeftUsers]) {
        NSMutableArray* filteredMembers = [[NSMutableArray alloc] init];
        
        for (MXRoomMember* member in membersList) {
            if (member.membership != MXMembershipLeave) {
                [filteredMembers addObject:member];
            }
        }
        
        membersList = filteredMembers;
    }
    
    members = [membersList sortedArrayUsingComparator:^NSComparisonResult(MXRoomMember *member1, MXRoomMember *member2) {
        // Move banned and left members at the end of the list
        if (member1.membership == MXMembershipLeave || member1.membership == MXMembershipBan) {
            if (member2.membership != MXMembershipLeave && member2.membership != MXMembershipBan) {
                return NSOrderedDescending;
            }
        } else if (member2.membership == MXMembershipLeave || member2.membership == MXMembershipBan) {
            return NSOrderedAscending;
        }
        
        // Move invited members just before left and banned members
        if (member1.membership == MXMembershipInvite) {
            if (member2.membership != MXMembershipInvite) {
                return NSOrderedDescending;
            }
        } else if (member2.membership == MXMembershipInvite) {
            return NSOrderedAscending;
        }
        
        if ([[AppSettings sharedSettings] sortMembersUsingLastSeenTime]) {
            // Get the users that correspond to these members
            MatrixSDKHandler *mxHandler = [MatrixSDKHandler sharedHandler];
            MXUser *user1 = [mxHandler.mxSession userWithUserId:member1.userId];
            MXUser *user2 = [mxHandler.mxSession userWithUserId:member2.userId];
            
            // Move users who are not online or unavailable at the end (before invited users)
            if ((user1.presence == MXPresenceOnline) || (user1.presence == MXPresenceUnavailable)) {
                if ((user2.presence != MXPresenceOnline) && (user2.presence != MXPresenceUnavailable)) {
                    return NSOrderedAscending;
                }
            } else if ((user2.presence == MXPresenceOnline) || (user2.presence == MXPresenceUnavailable)) {
                return NSOrderedDescending;
            } else {
                // Here both users are neither online nor unavailable (the lastActive ago is useless)
                // We will sort them according to their display, by keeping in front the offline users
                if (user1.presence == MXPresenceOffline) {
                    if (user2.presence != MXPresenceOffline) {
                        return NSOrderedAscending;
                    }
                } else if (user2.presence == MXPresenceOffline) {
                    return NSOrderedDescending;
                }
                return [[self.mxRoom.state memberName:member1.userId] compare:[self.mxRoom.state memberName:member2.userId] options:NSCaseInsensitiveSearch];
            }
            
            // Consider user's lastActive ago value
            if (user1.lastActiveAgo < user2.lastActiveAgo) {
                return NSOrderedAscending;
            } else if (user1.lastActiveAgo == user2.lastActiveAgo) {
                return [[self.mxRoom.state memberName:member1.userId] compare:[self.mxRoom.state memberName:member2.userId] options:NSCaseInsensitiveSearch];
            }
            return NSOrderedDescending;
        } else {
            // Move user without display name at the end (before invited users)
            if (member1.displayname.length) {
                if (!member2.displayname.length) {
                    return NSOrderedAscending;
                }
            } else if (member2.displayname.length) {
                return NSOrderedDescending;
            }
            
            return [[self.mxRoom.state memberName:member1.userId] compare:[self.mxRoom.state memberName:member2.userId] options:NSCaseInsensitiveSearch];
        }
    }];
    
    self.membersListButtonItem.enabled = members.count != 0;
}

- (void)showRoomMembers {
    // Dismiss keyboard
    [self dismissKeyboard];
    
    [self updateRoomMembers];
    
    // check if there is some members to display
    // else it makes no sense to display the list
    if (0 == members.count) {
        return;
    }
    
    self.membersView.hidden = NO;
    [self.membersTableView reloadData];
}

- (void)hideRoomMembers {
    self.membersView.hidden = YES;
    members = nil;
    // Force a reload to release all table cells (and then stop running timer)
    [self.membersTableView reloadData];
}

# pragma mark - Attachment handling

- (void)showAttachmentView:(UIGestureRecognizer *)gestureRecognizer {
    MXCImageView *attachment = (MXCImageView*)gestureRecognizer.view;
    [self dismissKeyboard];
    
    // Retrieve attachment information
    NSDictionary *content = attachment.mediaInfo;
    NSUInteger msgtype = ((NSNumber*)content[@"msgtype"]).unsignedIntValue;
    if (msgtype == RoomMessageTypeImage) {
        NSString *url = content[@"url"];
        if (url.length) {
            highResImageView = [[MXCImageView alloc] initWithFrame:self.membersView.frame];
            highResImageView.stretchable = YES;
            highResImageView.fullScreen = YES;
            highResImageView.mediaFolder = self.roomId;
            [highResImageView setImageURL:url withPreviewImage:attachment.image];
            
            // Add tap recognizer to hide attachment
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideAttachmentView)];
            [tap setNumberOfTouchesRequired:1];
            [tap setNumberOfTapsRequired:1];
            [highResImageView addGestureRecognizer:tap];
            highResImageView.userInteractionEnabled = YES;
        }
    } else if (msgtype == RoomMessageTypeVideo) {
        NSString *url =content[@"url"];
        if (url.length) {
            NSString *mimetype = nil;
            if (content[@"info"]) {
                mimetype = content[@"info"][@"mimetype"];
            }
            AVAudioSessionCategory = [[AVAudioSession sharedInstance] category];
            [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
            videoPlayer = [[MPMoviePlayerController alloc] init];
            if (videoPlayer != nil) {
                videoPlayer.scalingMode = MPMovieScalingModeAspectFit;
                [self.view addSubview:videoPlayer.view];
                [videoPlayer setFullscreen:YES animated:NO];
                [[NSNotificationCenter defaultCenter] addObserver:self
                                                         selector:@selector(moviePlayerPlaybackDidFinishNotification:)
                                                             name:MPMoviePlayerPlaybackDidFinishNotification
                                                           object:nil];
                [[NSNotificationCenter defaultCenter] addObserver:self
                                                         selector:@selector(moviePlayerWillExitFullscreen:)
                                                             name:MPMoviePlayerWillExitFullscreenNotification
                                                           object:videoPlayer];
                selectedVideoURL = url;
                
                // check if the file is a local one
                // could happen because a media upload has failed
                if ([[NSFileManager defaultManager] fileExistsAtPath:selectedVideoURL]) {
                    selectedVideoCachePath = selectedVideoURL;
                } else {
                    selectedVideoCachePath = [MediaManager cachePathForMediaURL:selectedVideoURL andType:mimetype inFolder:self.roomId];
                }
                                
                if ([[NSFileManager defaultManager] fileExistsAtPath:selectedVideoCachePath]) {
                    videoPlayer.contentURL = [NSURL fileURLWithPath:selectedVideoCachePath];
                    [videoPlayer play];
                } else {
                    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMediaDownloadEnd:) name:kMediaDownloadDidFinishNotification object:nil];
                    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onMediaDownloadEnd:) name:kMediaDownloadDidFailNotification object:nil];
                    [MediaManager downloadMediaFromURL:selectedVideoURL withType:mimetype inFolder:self.roomId];
                }
            }
        }
    } else if (msgtype == RoomMessageTypeAudio) {
    } else if (msgtype == RoomMessageTypeLocation) {
    }
}

- (void)onMediaDownloadEnd:(NSNotification *)notif {
    if ([notif.object isKindOfClass:[NSString class]]) {
        NSString* url = notif.object;
        if ([url isEqualToString:selectedVideoURL]) {
            // remove the observers
            [[NSNotificationCenter defaultCenter] removeObserver:self name:kMediaDownloadDidFinishNotification object:nil];
            [[NSNotificationCenter defaultCenter] removeObserver:self name:kMediaDownloadDidFailNotification object:nil];
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:selectedVideoCachePath]) {
                videoPlayer.contentURL = [NSURL fileURLWithPath:selectedVideoCachePath];
                [videoPlayer play];
            } else {
                NSLog(@"Video Download failed"); // TODO we should notify user
                [self hideAttachmentView];
            }
        }
    }
}

- (void)hideAttachmentView {
    selectedVideoURL = nil;
    selectedVideoCachePath = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerPlaybackDidFinishNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MPMoviePlayerWillExitFullscreenNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kMediaDownloadDidFinishNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kMediaDownloadDidFailNotification object:nil];
    
    [self dismissAttachmentImageViews];
    
    // Restore audio category
    if (AVAudioSessionCategory) {
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategory error:nil];
    }
    if (videoPlayer) {
        [videoPlayer stop];
        [videoPlayer setFullscreen:NO];
        [videoPlayer.view removeFromSuperview];
        videoPlayer = nil;
    }
}

- (void)moviePlayerWillExitFullscreen:(NSNotification*)notification {
    if (notification.object == videoPlayer) {
        [self hideAttachmentView];
    }
}

- (void)moviePlayerPlaybackDidFinishNotification:(NSNotification *)notification {
    NSDictionary *notificationUserInfo = [notification userInfo];
    NSNumber *resultValue = [notificationUserInfo objectForKey:MPMoviePlayerPlaybackDidFinishReasonUserInfoKey];
    MPMovieFinishReason reason = [resultValue intValue];
    
    // error cases
    if (reason == MPMovieFinishReasonPlaybackError) {
        NSError *mediaPlayerError = [notificationUserInfo objectForKey:@"error"];
        if (mediaPlayerError) {
            NSLog(@"Playback failed with error description: %@", [mediaPlayerError localizedDescription]);
            [self hideAttachmentView];
            //Alert user
            [[AppDelegate theDelegate] showErrorAsAlert:mediaPlayerError];
        }
    }
}

- (void)moviePlayerThumbnailImageRequestDidFinishNotification:(NSNotification *)notification {
    // Finalize video attachment
    UIImage* videoThumbnail = [[notification userInfo] objectForKey:MPMoviePlayerThumbnailImageKey];
    NSURL* selectedVideo = [tmpVideoPlayer contentURL];
    [tmpVideoPlayer stop];
    tmpVideoPlayer = nil;
    
    [self sendVideo:selectedVideo withThumbnail:videoThumbnail];
}

- (void)sendVideoContent:(NSMutableDictionary*)videoContent localEvent:(MXEvent*)localEvent {
    NSData* videoData = [NSData dataWithContentsOfFile:[videoContent valueForKey:@"url"]];
    
    // sanity check
    if (videoData) {
        NSMutableDictionary* videoInfo = [videoContent valueForKey:@"info"];

        MediaLoader *videoUploader = [MediaManager prepareUploaderWithId:localEvent.eventId initialRange:0.1 andRange:0.9 inFolder:self.roomId];
        [videoUploader uploadData:videoData mimeType:videoInfo[@"mimetype"] success:^(NSString *url) {
            
            // remove the tmp file
            [[NSFileManager defaultManager] removeItemAtPath:[videoInfo valueForKey:@"url"] error:nil];
            // remove the related uploadLoader
            [MediaManager removeUploaderWithId:localEvent.eventId inFolder:self.roomId];
            // store the video file in the cache
            // there is no reason to download an oneself uploaded media
            [MediaManager cacheMediaData:videoData forURL:url andType:videoInfo[@"mimetype"] inFolder:self.roomId];
            
            [videoContent setValue:url forKey:@"url"];
            [self sendMessage:videoContent withLocalEvent:localEvent];
        } failure:^(NSError *error) {
            NSLog(@"Video upload failed");
            // check if the upload is still defined
            // it could have been cancelled with an external events
            if ([MediaManager existingUploaderWithId:localEvent.eventId inFolder:self.roomId]) {
                [MediaManager removeUploaderWithId:localEvent.eventId inFolder:self.roomId];
                [self handleError:error forLocalEvent:localEvent];
            }
        }];
    }
    else {
        NSLog(@"Attach video failed: no data");
        [self handleError:nil forLocalEvent:localEvent];
    }
}

- (void)sendVideo:(NSURL*)videoURL withThumbnail:(UIImage*)videoThumbnail {
    if (videoThumbnail && videoURL) {
        // Prepare video thumbnail description
        NSUInteger thumbnailSize = ROOM_MESSAGE_MAX_ATTACHMENTVIEW_WIDTH;
        UIImage *thumbnail = [MXCTools resize:videoThumbnail toFitInSize:CGSizeMake(thumbnailSize, thumbnailSize)];
        
        // Create the local event displayed during uploading
        MXEvent *localEvent = [self addLocalEchoEventForAttachedVideo:thumbnail videoPath:videoURL.path];
        
        NSMutableDictionary *infoDict = [localEvent.content valueForKey:@"info"];
        NSMutableDictionary *thumbnailInfo = [infoDict valueForKey:@"thumbnail_info"];
        NSData *thumbnailData = [NSData dataWithContentsOfFile:[MediaManager cachePathForMediaURL:[infoDict valueForKey:@"thumbnail_url"] andType:[thumbnailInfo objectForKey:@"mimetype"] inFolder:self.roomId]];

        // Upload thumbnail
        MediaLoader *uploader = [MediaManager prepareUploaderWithId:localEvent.eventId initialRange:0 andRange:0.1 inFolder:self.roomId];
        [uploader uploadData:thumbnailData mimeType:[thumbnailInfo valueForKey:@"mimetype"] success:^(NSString *url) {
            [MediaManager removeUploaderWithId:localEvent.eventId inFolder:self.roomId];
            // Prepare content of attached video
            NSMutableDictionary *videoContent = [[NSMutableDictionary alloc] init];
            NSMutableDictionary *videoInfo = [[NSMutableDictionary alloc] init];
            [videoContent setValue:kMXMessageTypeVideo forKey:@"msgtype"];
            [videoInfo setValue:url forKey:@"thumbnail_url"];
            [videoInfo setValue:thumbnailInfo forKey:@"thumbnail_info"];
            
            // Convert video container to mp4
            AVURLAsset* videoAsset = [AVURLAsset URLAssetWithURL:videoURL options:nil];
            AVAssetExportSession *exportSession = [AVAssetExportSession exportSessionWithAsset:videoAsset presetName:AVAssetExportPresetMediumQuality];
            // Set output URL
            NSString * outputFileName = [NSString stringWithFormat:@"%.0f.mp4",[[NSDate date] timeIntervalSince1970]];
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
            NSString *cacheRoot = [paths objectAtIndex:0];
            NSURL *tmpVideoLocation = [NSURL fileURLWithPath:[cacheRoot stringByAppendingPathComponent:outputFileName]];
            exportSession.outputURL = tmpVideoLocation;
            // Check supported output file type
            NSArray *supportedFileTypes = exportSession.supportedFileTypes;
            if ([supportedFileTypes containsObject:AVFileTypeMPEG4]) {
                exportSession.outputFileType = AVFileTypeMPEG4;
                [videoInfo setValue:@"video/mp4" forKey:@"mimetype"];
            } else {
                NSLog(@"Unexpected case: MPEG-4 file format is not supported");
                // we send QuickTime movie file by default
                exportSession.outputFileType = AVFileTypeQuickTimeMovie;
                [videoInfo setValue:@"video/quicktime" forKey:@"mimetype"];
            }
            // Export video file and send it
            [exportSession exportAsynchronouslyWithCompletionHandler:^{
                // Check status
                if ([exportSession status] == AVAssetExportSessionStatusCompleted) {
                    AVURLAsset* asset = [AVURLAsset URLAssetWithURL:tmpVideoLocation
                                                            options:[NSDictionary dictionaryWithObjectsAndKeys:
                                                                     [NSNumber numberWithBool:YES],
                                                                     AVURLAssetPreferPreciseDurationAndTimingKey,
                                                                     nil]
                                         ];
                    
                    [videoInfo setValue:[NSNumber numberWithDouble:(1000 * CMTimeGetSeconds(asset.duration))] forKey:@"duration"];
                    NSArray *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
                    if (videoTracks.count > 0) {
                        AVAssetTrack *videoTrack = [videoTracks objectAtIndex:0];
                        CGSize videoSize = videoTrack.naturalSize;
                        [videoInfo setValue:[NSNumber numberWithUnsignedInteger:(NSUInteger)videoSize.width] forKey:@"w"];
                        [videoInfo setValue:[NSNumber numberWithUnsignedInteger:(NSUInteger)videoSize.height] forKey:@"h"];
                    }
                    
                    // Upload the video
                    [videoContent setValue:videoInfo forKey:@"info"];
                    [videoContent setValue:@"Video" forKey:@"body"];
                    [videoContent setValue:tmpVideoLocation.path forKey:@"url"];
                    localEvent.content = videoContent;
                    [self sendVideoContent:videoContent localEvent:localEvent];
                }
                else {
                    NSLog(@"Video export failed: %d", (int)[exportSession status]);
                    // remove tmp file (if any)
                    [[NSFileManager defaultManager] removeItemAtPath:[tmpVideoLocation path] error:nil];
                    [self handleError:nil forLocalEvent:localEvent];
                }
            }];
        } failure:^(NSError *error) {
            // check if the upload is still defined
            // it could have been cancelled with an external events
            if ([MediaManager existingUploaderWithId:localEvent.eventId inFolder:self.roomId]) {
                NSLog(@"Video thumbnail upload failed");
                [MediaManager removeUploaderWithId:localEvent.eventId inFolder:self.roomId];
                [self handleError:error forLocalEvent:localEvent];
            }
        }];
    }
    
    [self dismissMediaPicker];
}

#pragma mark - Keyboard handling

- (void)onKeyboardWillShow:(NSNotification *)notif {
    // get the keyboard size
    NSValue *rectVal = notif.userInfo[UIKeyboardFrameEndUserInfoKey];
    CGRect endRect = rectVal.CGRectValue;
    
    // IOS 8 triggers some unexpected keyboard events
    if ((endRect.size.height == 0) || (endRect.size.width == 0)) {
        return;
    }
    
    keyboardHeight = (endRect.origin.y == 0) ? endRect.size.width : endRect.size.height;
    
    // bottom view offset
    // Don't forget the offset related to tabBar
    CGFloat nextBottomViewContanst = keyboardHeight - [AppDelegate theDelegate].masterTabBarController.tabBar.frame.size.height;

    // the tableview bottom inset must also be updated
    UIEdgeInsets insets = self.messagesTableView.contentInset;
    // insets.bottom is the bottom part of the tableview content size which is not displayed
    // The bottom margin is equal to the keyboard height + controlview part which is greather than the tableview bottom margin.
    // The tableview bottom margin has the same value as the defauft bottom view height;
    insets.bottom = keyboardHeight + self.controlView.frame.size.height - defaultMessagesTableViewBottomConstraint;

    // compute the visible area (tableview + text input)
    CGFloat maxTextHeight = (self.view.frame.size.height - defaultMessagesTableViewBottomConstraint - keyboardHeight - self.navigationController.navigationBar.frame.size.height - MIN([UIApplication sharedApplication].statusBarFrame.size.height, [UIApplication sharedApplication].statusBarFrame.size.width));
    
    // get the animation info
    NSNumber *curveValue = [[notif userInfo] objectForKey:UIKeyboardAnimationCurveUserInfoKey];
    UIViewAnimationCurve animationCurve = curveValue.intValue;
    
    // the duration is ignored but it is better to define it
    double animationDuration = [[[notif userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    
    // remove pending observers to avoid duplicates
    // onKeyboardWillShow could be called several times bebore onKeyboardWillHide
    // because the keyboard height is updated (swicth to a chinese keyboard for example)
    // fixes https://github.com/matrix-org/matrix-ios-sdk/issues/4
    if (isKeyboardObserver) {
        [inputAccessoryView.superview removeObserver:self forKeyPath:@"frame"];
        [inputAccessoryView.superview removeObserver:self forKeyPath:@"center"];
        isKeyboardObserver = NO;
    }
    
    isKeyboardDisplayed = YES;
    
    [UIView animateWithDuration:animationDuration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | (animationCurve << 16) animations:^{
        
        // Move up control view
        // Don't forget the offset related to tabBar
        _controlViewBottomConstraint.constant = nextBottomViewContanst;
        
        // reduce the tableview height
        self.messagesTableView.contentInset = insets;
        
        // scroll the tableview content
        [self scrollToBottomAnimated:NO];
        
        // force to redraw the layout (else _controlViewBottomConstraint.constant will not be animated)
        [self.view layoutIfNeeded];
        
        // update the text input frame
        _messageTextView.maxHeight = maxTextHeight;
        [_messageTextView refreshHeight];
        
    } completion:^(BOOL finished) {
        // be warned when the keyboard frame is updated
        // used to trap the slide to close the keyboard
        [inputAccessoryView.superview addObserver:self forKeyPath:@"frame" options:0 context:nil];
        [inputAccessoryView.superview addObserver:self forKeyPath:@"center" options:0 context:nil];
        isKeyboardObserver = YES;
    }];
}

- (void)onKeyboardWillHide:(NSNotification *)notif {
    
    // onKeyboardWillHide seems being called several times by IOS
    if (isKeyboardObserver) {
        
        // IOS 8 / landscape issue
        // when the keyboard reaches the tabbar, it triggers UIKeyboardWillShowNotification events in loop
        // ensure that there is only one evene registration
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onKeyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
        
        [inputAccessoryView.superview removeObserver:self forKeyPath:@"frame"];
        [inputAccessoryView.superview removeObserver:self forKeyPath:@"center"];
        isKeyboardObserver = NO;
    }
    
    // get the keyboard size
    NSValue *rectVal = notif.userInfo[UIKeyboardFrameEndUserInfoKey];
    CGRect endRect = rectVal.CGRectValue;
    
    rectVal = notif.userInfo[UIKeyboardFrameBeginUserInfoKey];
    CGRect beginRect = rectVal.CGRectValue;
    
    // IOS 7/8 triggers some unexpected keyboard events
    if (!isKeyboardDisplayed) {
        return;
    }
    
    UIEdgeInsets insets = self.messagesTableView.contentInset;
    // insets.bottom is the bottom part of the tableview content size which is not displayed
    // The bottom margin is equal to the tabbar height + controlview part which is greather than the tableview bottom margin.
    // The tableview bottom margin has the same value as the defauft bottom view height.
    insets.bottom = [AppDelegate theDelegate].masterTabBarController.tabBar.frame.size.height + (self.controlView.frame.size.height - defaultMessagesTableViewBottomConstraint);
    
    isKeyboardDisplayed = NO;
    
    // do not animate if the both rect are the same
    // but ensure that the fields are properly resetted
    // e.g. when the user swipes to hide the keyboard
    // this method is called with invalid rects
    // animationDuration is ignored because of the animation curve
    // use it to be sure that it will be broken with any new IOS update
    if (CGRectEqualToRect(endRect, beginRect)) {
        
        self.messagesTableView.contentInset = insets;
        _controlViewBottomConstraint.constant = defaultControlViewBottomConstraint;
        _messagesTableViewBottomConstraint.constant = defaultMessagesTableViewBottomConstraint;
        
        [self.view layoutIfNeeded];
        
    } else {
        
        // get the animation info
        NSNumber *curveValue = [[notif userInfo] objectForKey:UIKeyboardAnimationCurveUserInfoKey];
        UIViewAnimationCurve animationCurve = curveValue.intValue;
        
        // the duration is ignored but it is better to define it
        double animationDuration = [[[notif userInfo] objectForKey:UIKeyboardAnimationDurationUserInfoKey] doubleValue];
        
        // animate the keyboard closing
        [UIView animateWithDuration:animationDuration delay:0 options:UIViewAnimationOptionBeginFromCurrentState | (animationCurve << 16) animations:^{
            
            _controlViewBottomConstraint.constant = defaultControlViewBottomConstraint;
            _messagesTableViewBottomConstraint.constant = defaultMessagesTableViewBottomConstraint;
            
            self.messagesTableView.contentInset = insets;
            [self.view layoutIfNeeded];
            
        } completion:^(BOOL finished) {
        }];
    }
}

- (void)dismissKeyboard {
    // Hide the keyboard
    [_messageTextView resignFirstResponder];
    [_roomTitleView dismissKeyboard];
}

#pragma mark - UITableView data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // Check table view members vs messages
    if (tableView == self.membersTableView) {
        return members.count;
    }
    
    if (backPaginationAddedMsgNb) {
        // Here some old messages have been added to messages during back pagination.
        // Stop table refreshing, the table will be refreshed at the end of pagination
        return 0;
    }
    return messages.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Check table view members vs messages
    if (tableView == self.membersTableView) {
        // Use the same default height than message cell
        return ROOM_MESSAGE_CELL_DEFAULT_HEIGHT;
    }
    
    // Compute here height of message cell
    CGFloat rowHeight;
    RoomMessage* message = nil;
    @synchronized(self) {
        if (indexPath.row < messages.count) {
            message = [messages objectAtIndex:indexPath.row];
        }
    }
    
    // Sanity check
    if (!message) {
        return 0;
    }
    // Else compute height of message content (The maximum width available for the textview must be updated dynamically)
    message.maxTextViewWidth = self.messagesTableView.frame.size.width - ROOM_MESSAGE_CELL_TEXTVIEW_LEADING_AND_TRAILING_CONSTRAINT_TO_SUPERVIEW;
    rowHeight = message.contentSize.height;
    
    // Add top margin
    if (message.messageType == RoomMessageTypeText) {
        rowHeight += ROOM_MESSAGE_CELL_DEFAULT_TEXTVIEW_TOP_CONST;
    } else {
        rowHeight += ROOM_MESSAGE_CELL_DEFAULT_ATTACHMENTVIEW_TOP_CONST;
    }
    
    // Check whether the previous message has been sent by the same user.
    // The user's picture and name are displayed only for the first message.
    BOOL shouldHideSenderInfo = NO;
    if (indexPath.row) {
        @synchronized(self) {
            RoomMessage *previousMessage = [messages objectAtIndex:indexPath.row - 1];
            shouldHideSenderInfo = [message hasSameSenderAsRoomMessage:previousMessage];
        }
    }
    
    if (shouldHideSenderInfo) {
        // Reduce top margin -> row height reduction
        rowHeight += ROOM_MESSAGE_CELL_HEIGHT_REDUCTION_WHEN_SENDER_INFO_IS_HIDDEN;
    } else {
        // We consider a minimun cell height in order to display correctly user's picture
        if (rowHeight < ROOM_MESSAGE_CELL_DEFAULT_HEIGHT) {
            rowHeight = ROOM_MESSAGE_CELL_DEFAULT_HEIGHT;
        }
    }
    return rowHeight;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    MatrixSDKHandler *mxHandler = [MatrixSDKHandler sharedHandler];
    
    // Check table view members vs messages
    if (tableView == self.membersTableView) {
        RoomMemberTableCell *memberCell = [tableView dequeueReusableCellWithIdentifier:@"RoomMemberCell" forIndexPath:indexPath];
        if (indexPath.row < members.count) {
            MXRoomMember *roomMember = [members objectAtIndex:indexPath.row];
            [memberCell setRoomMember:roomMember withRoom:self.mxRoom];
            if ([roomMember.userId isEqualToString:mxHandler.userId]) {
                memberCell.typingBadge.hidden = YES; //hide typing badge for the current user
            } else {
                memberCell.typingBadge.hidden = ([currentTypingUsers indexOfObject:roomMember.userId] == NSNotFound);
                if (!memberCell.typingBadge.hidden) {
                    [memberCell.typingBadge.superview bringSubviewToFront:memberCell.typingBadge];
                }
            }
        }
        return memberCell;
    }
    
    // Handle here room message cells
    RoomMessage* message = nil;
    @synchronized(self) {
        if (indexPath.row < messages.count) {
            message = [messages objectAtIndex:indexPath.row];
        }
    }
    // Sanity check
    if (!message) {
        return [[UITableViewCell alloc] initWithFrame:CGRectZero];
    }
    // Else prepare the message cell
    RoomMessageTableCell *cell;
    BOOL isIncomingMsg = NO;
    if ([message.senderId isEqualToString:mxHandler.userId]) {
        cell = [tableView dequeueReusableCellWithIdentifier:@"OutgoingMessageCell" forIndexPath:indexPath];
    } else {
        cell = [tableView dequeueReusableCellWithIdentifier:@"IncomingMessageCell" forIndexPath:indexPath];
        isIncomingMsg = YES;
    }
    
    // Keep reference on message
    cell.message = message;
    
    // set the media folders
    cell.pictureView.mediaFolder = kMediaManagerThumbnailFolder;
    cell.attachmentView.mediaFolder = self.roomId;
    
    // Check whether the previous message has been sent by the same user.
    // The user's picture and name are displayed only for the first message.
    BOOL shouldHideSenderInfo = NO;
    if (indexPath.row) {
        @synchronized(self) {
            RoomMessage *previousMessage = [messages objectAtIndex:indexPath.row - 1];
            shouldHideSenderInfo = [message hasSameSenderAsRoomMessage:previousMessage];
        }
    }
    // Handle sender's picture and adjust view's constraints
    if (shouldHideSenderInfo) {
        cell.pictureView.hidden = YES;
        cell.msgTextViewTopConstraint.constant = ROOM_MESSAGE_CELL_DEFAULT_TEXTVIEW_TOP_CONST + ROOM_MESSAGE_CELL_HEIGHT_REDUCTION_WHEN_SENDER_INFO_IS_HIDDEN;
        cell.attachViewTopConstraint.constant = ROOM_MESSAGE_CELL_DEFAULT_ATTACHMENTVIEW_TOP_CONST + ROOM_MESSAGE_CELL_HEIGHT_REDUCTION_WHEN_SENDER_INFO_IS_HIDDEN;
    } else {
        cell.pictureView.hidden = NO;
        cell.msgTextViewTopConstraint.constant = ROOM_MESSAGE_CELL_DEFAULT_TEXTVIEW_TOP_CONST;
        cell.attachViewTopConstraint.constant = ROOM_MESSAGE_CELL_DEFAULT_ATTACHMENTVIEW_TOP_CONST;
        // Handle user's picture
        NSString *avatarThumbURL = nil;
        if (message.senderAvatarUrl) {
            // Suppose this url is a matrix content uri, we use SDK to get the well adapted thumbnail from server
            avatarThumbURL = [mxHandler thumbnailURLForContent:message.senderAvatarUrl inViewSize:cell.pictureView.frame.size withMethod:MXThumbnailingMethodCrop];
        }
        [cell.pictureView setImageURL:avatarThumbURL withPreviewImage:[UIImage imageNamed:@"default-profile"]];
        [cell.pictureView.layer setCornerRadius:cell.pictureView.frame.size.width / 2];
        cell.pictureView.clipsToBounds = YES;
        cell.pictureView.backgroundColor = [UIColor redColor];
    }
    
    [self addPictureViewTapGesture:cell];
    
    // Adjust top constraint constant for dateTime labels container, and hide it by default
    if (message.messageType == RoomMessageTypeText) {
        cell.dateTimeLabelContainerTopConstraint.constant = cell.msgTextViewTopConstraint.constant;
    } else {
        cell.dateTimeLabelContainerTopConstraint.constant = cell.attachViewTopConstraint.constant;
    }
    cell.dateTimeLabelContainer.hidden = YES;
    
    BOOL displayMsgTimestamp = (nil != dateFormatter);
    
    // Update incoming/outgoing message layout
    if (isIncomingMsg) {
        IncomingMessageTableCell* incomingMsgCell = (IncomingMessageTableCell*)cell;
        // Display user's display name except if the name appears in the displayed text (see emote and membership event)
        incomingMsgCell.userNameLabel.hidden = (shouldHideSenderInfo || message.startsWithSenderName);
        incomingMsgCell.userNameLabel.text = message.senderName;
        // Set typing badge visibility
        incomingMsgCell.typingBadge.hidden = (cell.pictureView.hidden || ([currentTypingUsers indexOfObject:message.senderId] == NSNotFound));
        if (!incomingMsgCell.typingBadge.hidden) {
            [incomingMsgCell.typingBadge.superview bringSubviewToFront:incomingMsgCell.typingBadge];
        }
    } else {
        // Add unsent label for failed components
        CGFloat yPosition = (message.messageType == RoomMessageTypeText) ? ROOM_MESSAGE_TEXTVIEW_MARGIN : -ROOM_MESSAGE_TEXTVIEW_MARGIN;
        [message checkComponentsHeight];
        for (RoomMessageComponent *component in message.components) {
            if (component.style == RoomMessageComponentStyleFailed) {
                UIButton *unsentButton = [[UIButton alloc] initWithFrame:CGRectMake(0, yPosition, 58 , 20)];
                
                [unsentButton setTitle:@"Unsent" forState:UIControlStateNormal];
                [unsentButton setTitle:@"Unsent" forState:UIControlStateSelected];
                [unsentButton setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
                [unsentButton setTitleColor:[UIColor redColor] forState:UIControlStateSelected];
             
                unsentButton.backgroundColor = [UIColor whiteColor];
                unsentButton.titleLabel.font =  [UIFont systemFontOfSize:14];
                
                // add a dummy label to store the event ID
                // so the message will be easily found when the button will be tapped
                UILabel* hiddenLabel = [[UILabel alloc] init];
                hiddenLabel.tag = HIDDEN_UNSENT_MSG_LABEL;
                hiddenLabel.text = component.eventId;
                hiddenLabel.hidden = YES;
                hiddenLabel.frame = CGRectZero;
                hiddenLabel.userInteractionEnabled = YES;
                [unsentButton addSubview:hiddenLabel];
                
                [unsentButton addTarget:self action:@selector(onResendToggle:)  forControlEvents:UIControlEventTouchUpInside];
                
                [cell.dateTimeLabelContainer addSubview:unsentButton];
                cell.dateTimeLabelContainer.hidden = NO;
                cell.dateTimeLabelContainer.userInteractionEnabled = YES;
                
                // ensure that dateTimeLabelContainer is at front to catch the the tap event 
                [cell.dateTimeLabelContainer.superview bringSubviewToFront:cell.dateTimeLabelContainer];
            }
            yPosition += component.height;
        }
    }
    
    // Set message content
    message.maxTextViewWidth = self.messagesTableView.frame.size.width - ROOM_MESSAGE_CELL_TEXTVIEW_LEADING_AND_TRAILING_CONSTRAINT_TO_SUPERVIEW;
    CGSize contentSize = message.contentSize;
    if (message.messageType != RoomMessageTypeText) {
        cell.messageTextView.hidden = YES;
        cell.attachmentView.hidden = NO;
        // Update image view frame in order to center loading wheel (if any)
        CGRect frame = cell.attachmentView.frame;
        frame.size.width = contentSize.width;
        frame.size.height = contentSize.height;
        cell.attachmentView.frame = frame;
        
        NSString *url = message.thumbnailURL;
        if (message.messageType == RoomMessageTypeVideo) {
            cell.playIconView.hidden = NO;
        } else {
            cell.playIconView.hidden = YES;
        }
        UIImage *preview = nil;
        if (message.previewURL) {
            preview = [MediaManager loadCachePictureForURL:message.previewURL inFolder:self.roomId];
        }
        [cell.attachmentView setImageURL:url withPreviewImage:preview];

        if (url && message.attachmentURL && message.attachmentInfo) {
            // Add tap recognizer to open attachment
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showAttachmentView:)];
            [tap setNumberOfTouchesRequired:1];
            [tap setNumberOfTapsRequired:1];
            [tap setDelegate:self];
            [cell.attachmentView addGestureRecognizer:tap];
            // Store attachment content description used in showAttachmentView:
            cell.attachmentView.mediaInfo = @{@"msgtype" : [NSNumber numberWithUnsignedInt:message.messageType],
                                              @"url" : message.attachmentURL,
                                              @"info" : message.attachmentInfo};
        }
        
        [cell startProgressUI];
        
        // wait after upload info
        if (message.isUploadInProgress) {
            [((OutgoingMessageTableCell*)cell) startUploadAnimating];
            cell.attachmentView.hideActivityIndicator = YES;
        } else {
            cell.attachmentView.hideActivityIndicator = NO;
        }
        
        // Adjust Attachment width constant
        cell.attachViewWidthConstraint.constant = contentSize.width;
    } else {
        cell.attachmentView.hidden = YES;
        cell.playIconView.hidden = YES;
        cell.messageTextView.hidden = NO;
        if (!isIncomingMsg) {
            // Adjust horizontal position for outgoing messages (text is left aligned, but the textView should be right aligned)
            CGFloat leftInset = message.maxTextViewWidth - contentSize.width;
            cell.messageTextView.contentInset = UIEdgeInsetsMake(0, leftInset, 0, -leftInset);
        }
        cell.messageTextView.attributedText = message.attributedTextMessage;
    }
    
    // Add a long tap gesture on the progressView
    // manage it in the storyboard does not work properly
    // -> The gesture view is always the same i.e. the latest composed one.
    // Note: only the download can be cancelled
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onProgressLongTap:)];
    [cell.progressView addGestureRecognizer:longPress];
    
    // Handle timestamp display
    if (displayMsgTimestamp) {
        // Add datetime label for each component
        cell.dateTimeLabelContainer.hidden = NO;
        [message checkComponentsHeight];
        CGFloat yPosition = (message.messageType == RoomMessageTypeText) ? ROOM_MESSAGE_TEXTVIEW_MARGIN : -ROOM_MESSAGE_TEXTVIEW_MARGIN;
        for (RoomMessageComponent *component in message.components) {
            if (component.date && (component.style != RoomMessageComponentStyleFailed)) {
                UILabel *dateTimeLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, yPosition, cell.dateTimeLabelContainer.frame.size.width , 20)];
                dateTimeLabel.text = [dateFormatter stringFromDate:component.date];
                if (isIncomingMsg) {
                    dateTimeLabel.textAlignment = NSTextAlignmentRight;
                } else {
                    dateTimeLabel.textAlignment = NSTextAlignmentLeft;
                }
                dateTimeLabel.textColor = [UIColor lightGrayColor];
                dateTimeLabel.font = [UIFont systemFontOfSize:12];
                dateTimeLabel.adjustsFontSizeToFitWidth = YES;
                dateTimeLabel.minimumScaleFactor = 0.6;
                [dateTimeLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
                [cell.dateTimeLabelContainer addSubview:dateTimeLabel];
                // Force dateTimeLabel in full width (to handle auto-layout in case of screen rotation)
                NSLayoutConstraint *leftConstraint = [NSLayoutConstraint constraintWithItem:dateTimeLabel
                                                                                  attribute:NSLayoutAttributeLeading
                                                                                  relatedBy:NSLayoutRelationEqual
                                                                                     toItem:cell.dateTimeLabelContainer
                                                                                  attribute:NSLayoutAttributeLeading
                                                                                 multiplier:1.0
                                                                                   constant:0];
                NSLayoutConstraint *rightConstraint = [NSLayoutConstraint constraintWithItem:dateTimeLabel
                                                                                   attribute:NSLayoutAttributeTrailing
                                                                                   relatedBy:NSLayoutRelationEqual
                                                                                      toItem:cell.dateTimeLabelContainer
                                                                                   attribute:NSLayoutAttributeTrailing
                                                                                  multiplier:1.0
                                                                                    constant:0];
                // Vertical constraints are required for iOS > 8
                NSLayoutConstraint *topConstraint = [NSLayoutConstraint constraintWithItem:dateTimeLabel
                                                                                 attribute:NSLayoutAttributeTop
                                                                                 relatedBy:NSLayoutRelationEqual
                                                                                    toItem:cell.dateTimeLabelContainer
                                                                                 attribute:NSLayoutAttributeTop
                                                                                multiplier:1.0
                                                                                  constant:yPosition];
                NSLayoutConstraint *heightConstraint = [NSLayoutConstraint constraintWithItem:dateTimeLabel
                                                                                    attribute:NSLayoutAttributeHeight
                                                                                    relatedBy:NSLayoutRelationEqual
                                                                                       toItem:nil
                                                                                    attribute:NSLayoutAttributeNotAnAttribute
                                                                                   multiplier:1.0
                                                                                     constant:20];
                if ([NSLayoutConstraint respondsToSelector:@selector(activateConstraints:)]) {
                    [NSLayoutConstraint activateConstraints:@[leftConstraint, rightConstraint, topConstraint, heightConstraint]];
                } else {
                    [cell.dateTimeLabelContainer addConstraint:leftConstraint];
                    [cell.dateTimeLabelContainer addConstraint:rightConstraint];
                    [cell.dateTimeLabelContainer addConstraint:topConstraint];
                    [dateTimeLabel addConstraint:heightConstraint];
                }
            }
            yPosition += component.height;
        }
    }
    
    return cell;
}

#pragma mark - UITableView delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // Check table view members vs messages
    if (tableView == self.membersTableView) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    } else if (tableView == self.messagesTableView) {
        // Dismiss keyboard when user taps on messages table view content
        [self dismissKeyboard];
    }
}

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath*)indexPath {
    // Release here resources, and restore reusable cells
    
    // Check table view members vs messages
    if (tableView == self.membersTableView) {
        RoomMemberTableCell *memberCell = (RoomMemberTableCell*)cell;
        // Stop potential timer used to refresh member's presence
        [memberCell setRoomMember:nil withRoom:nil];
    } else if (tableView == self.messagesTableView) {
        RoomMessageTableCell *msgCell = (RoomMessageTableCell*)cell;
        if ([cell isKindOfClass:[OutgoingMessageTableCell class]]) {
            OutgoingMessageTableCell *outgoingMsgCell = (OutgoingMessageTableCell*)cell;
            // Hide potential loading wheel
            [outgoingMsgCell stopAnimating];
        }
        msgCell.message = nil;
        
        // Remove all gesture recognizer
        while (msgCell.attachmentView.gestureRecognizers.count) {
            [msgCell.attachmentView removeGestureRecognizer:msgCell.attachmentView.gestureRecognizers[0]];
        }
        // Remove potential dateTime (or unsent) label(s)
        if (msgCell.dateTimeLabelContainer.subviews.count > 0) {
            if ([NSLayoutConstraint respondsToSelector:@selector(deactivateConstraints:)]) {
                [NSLayoutConstraint deactivateConstraints:msgCell.dateTimeLabelContainer.constraints];
            } else {
                [msgCell.dateTimeLabelContainer removeConstraints:msgCell.dateTimeLabelContainer.constraints];
            }
            for (UIView *view in msgCell.dateTimeLabelContainer.subviews) {
                [view removeFromSuperview];
            }
        }
        
        [msgCell stopProgressUI];
        
        // Remove long tap gesture on the progressView
        while (msgCell.progressView.gestureRecognizers.count) {
            [msgCell.progressView removeGestureRecognizer:msgCell.progressView.gestureRecognizers[0]];
        }
    }
}

// Detect vertical bounce at the top of the tableview to trigger pagination
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    if (scrollView == self.messagesTableView) {
        // paginate ?
        if (scrollView.contentOffset.y < -64) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self triggerBackPagination];
            });
        }
    }
}

#pragma mark - HPGrowingTextView delegate

- (void)growingTextViewDidEndEditing:(HPGrowingTextView *)growingTextView {
    if (growingTextView == _messageTextView) {
        [self handleTypingNotification:NO];
    }
}

- (void)growingTextViewDidChange:(HPGrowingTextView *)growingTextView {
    if (growingTextView == _messageTextView) {
        NSString *msg = _messageTextView.text;
        
        // save the last edited text
        // to do not send unexpected typing events
        // HPGrowingTextView triggers growingTextViewDidChange event when it recomposes itself
        if (![lastEditedText isEqualToString:msg]) {
            lastEditedText = msg;
            if (msg.length) {
                [self handleTypingNotification:YES];
                _sendBtn.enabled = YES;
                _sendBtn.alpha = 1;
                // Reset potential placeholder (used in case of wrong command usage)
                _messageTextView.placeholder = nil;
            } else {
                [self handleTypingNotification:NO];
                _sendBtn.enabled = NO;
                _sendBtn.alpha = 0.5;
            }
        }
    }
}

- (void)growingTextView:(HPGrowingTextView *)growingTextView willChangeHeight:(float)height {
    // margins between _messageTextView and its superview (controlView)
    CGFloat controlViewHeight = height + self.controlView.frame.size.height - _messageTextView.frame.size.height;
    
    // update the controlView height
    _controlViewHeightConstraint.constant = controlViewHeight;
    
    UIEdgeInsets insets = self.messagesTableView.contentInset;
    
    // if the keyboard is not displayed
    if (!isKeyboardDisplayed) {
        insets.bottom = [AppDelegate theDelegate].masterTabBarController.tabBar.frame.size.height + controlViewHeight - defaultMessagesTableViewBottomConstraint;
    } else {
        insets.bottom = keyboardHeight + controlViewHeight - defaultMessagesTableViewBottomConstraint;
    }
    
    self.messagesTableView.contentInset = insets;
    
    if (isKeyboardDisplayed) {
        // scroll to bottom if the user did not scroll to the last 5 pixels of the tableview
        // add a little margin to avoid approximated values issue
        if ((self.messagesTableView.contentSize.height - self.messagesTableView.contentOffset.y - 30) <= (self.messagesTableView.frame.size.height - self.messagesTableView.contentInset.bottom)) {
            // force to render the view
            [self.view layoutIfNeeded];
            // to have a valid sscroll to bottom
            [self scrollToBottomAnimated:NO];
        }
    } else {
        // force to render the view
        [self.view layoutIfNeeded];
    }
}

#pragma mark - UITextField delegate

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    NSString *alertMsg = nil;
    
    if (textField == _roomTitleView.displayNameTextField) {
        // Check whether the user has enough power to rename the room
        MXRoomPowerLevels *powerLevels = [self.mxRoom.state powerLevels];
        NSUInteger userPowerLevel = [powerLevels powerLevelOfUserWithUserID:[MatrixSDKHandler sharedHandler].userId];
        if (userPowerLevel >= [powerLevels minimumPowerLevelForSendingEventAsStateEvent:kMXEventTypeStringRoomName]) {
            // Only the room name is edited here, update the text field with the room name
            textField.text = self.mxRoom.state.name;
            textField.backgroundColor = [UIColor whiteColor];
        } else {
            alertMsg = @"You are not authorized to edit this room name";
        }
        
        // Check whether the user is allowed to change room topic
        if (userPowerLevel >= [powerLevels minimumPowerLevelForSendingEventAsStateEvent:kMXEventTypeStringRoomTopic]) {
            // Show topic text field even if the current value is nil
            _roomTitleView.hiddenTopic = NO;
            if (alertMsg) {
                // Here the user can only update the room topic, switch on room topic field (without displaying alert)
                alertMsg = nil;
                [_roomTitleView.topicTextField becomeFirstResponder];
                return NO;
            }
        }
    } else if (textField == _roomTitleView.topicTextField) {
        // Check whether the user has enough power to edit room topic
        MXRoomPowerLevels *powerLevels = [self.mxRoom.state powerLevels];
        NSUInteger userPowerLevel = [powerLevels powerLevelOfUserWithUserID:[MatrixSDKHandler sharedHandler].userId];
        if (userPowerLevel >= [powerLevels minimumPowerLevelForSendingEventAsStateEvent:kMXEventTypeStringRoomTopic]) {
            textField.backgroundColor = [UIColor whiteColor];
            [self.roomTitleView stopTopicAnimation];
        } else {
            alertMsg = @"You are not authorized to edit this room topic";
        }
    }
    
    if (alertMsg) {
        // Alert user
        __weak typeof(self) weakSelf = self;
        if (self.actionMenu) {
            [self.actionMenu dismiss:NO];
        }
        self.actionMenu = [[MXCAlert alloc] initWithTitle:nil message:alertMsg style:MXCAlertStyleAlert];
        self.actionMenu.cancelButtonIndex = [self.actionMenu addActionWithTitle:@"Cancel" style:MXCAlertActionStyleDefault handler:^(MXCAlert *alert) {
            weakSelf.actionMenu = nil;
        }];
        [self.actionMenu showInViewController:self];
        return NO;
    }
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    if (textField == _roomTitleView.displayNameTextField) {
        textField.backgroundColor = [UIColor clearColor];
        
        NSString *roomName = textField.text;
        if ((roomName.length || self.mxRoom.state.name.length) && [roomName isEqualToString:self.mxRoom.state.name] == NO) {
            [self startActivityIndicator];
            __weak typeof(self) weakSelf = self;
            [self.mxRoom setName:roomName success:^{
                [weakSelf stopActivityIndicator];
                // Refresh title display
                textField.text = weakSelf.mxRoom.state.displayname;
            } failure:^(NSError *error) {
                [weakSelf stopActivityIndicator];
                // Revert change
                textField.text = weakSelf.mxRoom.state.displayname;
                NSLog(@"Rename room failed: %@", error);
                //Alert user
                [[AppDelegate theDelegate] showErrorAsAlert:error];
            }];
        } else {
            // No change on room name, restore title with room displayName
            textField.text = self.mxRoom.state.displayname;
        }
    } else if (textField == _roomTitleView.topicTextField) {
        textField.backgroundColor = [UIColor clearColor];
        
        NSString *topic = textField.text;
        if ((topic.length || self.mxRoom.state.topic.length) && [topic isEqualToString:self.mxRoom.state.topic] == NO) {
            [self startActivityIndicator];
            __weak typeof(self) weakSelf = self;
            [self.mxRoom setTopic:topic success:^{
                [weakSelf stopActivityIndicator];
                // Hide topic field if empty
                weakSelf.roomTitleView.hiddenTopic = !textField.text.length;
            } failure:^(NSError *error) {
                [weakSelf stopActivityIndicator];
                // Revert change
                textField.text = weakSelf.mxRoom.state.topic;
                // Hide topic field if empty
                weakSelf.roomTitleView.hiddenTopic = !textField.text.length;
                NSLog(@"Topic room change failed: %@", error);
                //Alert user
                [[AppDelegate theDelegate] showErrorAsAlert:error];
            }];
        } else {
            // Hide topic field if empty
            _roomTitleView.hiddenTopic = !topic.length;
        }
    }
}

- (BOOL)textFieldShouldReturn:(UITextField*) textField {
    if (textField == _roomTitleView.displayNameTextField) {
        // "Next" key has been pressed
        [_roomTitleView.topicTextField becomeFirstResponder];
    } else {
        // "Done" key has been pressed
        [textField resignFirstResponder];
    }
    return YES;
}

#pragma mark - Actions

- (IBAction)onButtonPressed:(id)sender {
    if (sender == _sendBtn) {
        NSString *msgTxt = self.messageTextView.text;
        
        // Handle potential commands in room chat
        if ([self isIRCStyleCommand:msgTxt] == NO) {
            [self sendTextMessage:msgTxt];
        }
        
        self.messageTextView.text = nil;
        [self handleTypingNotification:NO];
        // disable send button
        _sendBtn.enabled = NO;
        _sendBtn.alpha = 0.5;
    } else if (sender == _optionBtn) {
        [self dismissKeyboard];
        
        // Display action menu: Add attachments, Invite user...
        __weak typeof(self) weakSelf = self;
        self.actionMenu = [[MXCAlert alloc] initWithTitle:@"Select an action:" message:nil style:MXCAlertStyleActionSheet];
        // Attachments
        [self.actionMenu addActionWithTitle:@"Attach" style:MXCAlertActionStyleDefault handler:^(MXCAlert *alert) {
            if (weakSelf) {
                // Ask for attachment type
                weakSelf.actionMenu = [[MXCAlert alloc] initWithTitle:@"Select an attachment type:" message:nil style:MXCAlertStyleActionSheet];
                [weakSelf.actionMenu addActionWithTitle:@"Media" style:MXCAlertActionStyleDefault handler:^(MXCAlert *alert) {
                    if (weakSelf) {
                        weakSelf.actionMenu = nil;
                        dispatch_async(dispatch_get_main_queue(), ^{
                            weakSelf.actionMenu = [[MXCAlert alloc] initWithTitle:@"Media:" message:nil style:MXCAlertStyleActionSheet];
                            
                            [weakSelf.actionMenu addActionWithTitle:@"Photo Library" style:MXCAlertActionStyleDefault handler:^(MXCAlert *alert) {
                                if (weakSelf) {
                                    weakSelf.actionMenu = nil;
                                    
                                    // Open media gallery
                                    UIImagePickerController *mediaPicker = [[UIImagePickerController alloc] init];
                                    mediaPicker.delegate = weakSelf;
                                    mediaPicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
                                    mediaPicker.allowsEditing = NO;
                                    mediaPicker.mediaTypes = [NSArray arrayWithObjects:(NSString *)kUTTypeImage, (NSString *)kUTTypeMovie, nil];
                                    [[AppDelegate theDelegate].masterTabBarController presentMediaPicker:mediaPicker];
                                }
                            }];
                            
                            [weakSelf.actionMenu addActionWithTitle:@"Take Photo or Video" style:MXCAlertActionStyleDefault handler:^(MXCAlert *alert) {
                                if (weakSelf) {
                                    weakSelf.actionMenu = nil;
                                    
                                    // Open media gallery
                                    UIImagePickerController *mediaPicker = [[UIImagePickerController alloc] init];
                                    mediaPicker.delegate = weakSelf;
                                    mediaPicker.sourceType = UIImagePickerControllerSourceTypeCamera;
                                    mediaPicker.allowsEditing = NO;
                                    mediaPicker.mediaTypes = [NSArray arrayWithObjects:(NSString *)kUTTypeImage, (NSString *)kUTTypeMovie, nil];
                                    [[AppDelegate theDelegate].masterTabBarController presentMediaPicker:mediaPicker];
                                }
                            }];
                            
                            weakSelf.actionMenu.cancelButtonIndex = [weakSelf.actionMenu addActionWithTitle:@"Cancel" style:MXCAlertActionStyleDefault handler:^(MXCAlert *alert) {
                                weakSelf.actionMenu = nil;
                            }];
                            [weakSelf.actionMenu showInViewController:weakSelf];
                            
                        });
                    }
                    
                }];
                weakSelf.actionMenu.cancelButtonIndex = [weakSelf.actionMenu addActionWithTitle:@"Cancel" style:MXCAlertActionStyleDefault handler:^(MXCAlert *alert) {
                    weakSelf.actionMenu = nil;
                }];
                [weakSelf.actionMenu showInViewController:weakSelf];
            }
        }];
        // Invitation
        [self.actionMenu addActionWithTitle:@"Invite" style:MXCAlertActionStyleDefault handler:^(MXCAlert *alert) {
            if (weakSelf) {
                // Ask for userId to invite
                weakSelf.actionMenu = [[MXCAlert alloc] initWithTitle:@"User ID:" message:nil style:MXCAlertStyleAlert];
                weakSelf.actionMenu.cancelButtonIndex = [weakSelf.actionMenu addActionWithTitle:@"Cancel" style:MXCAlertActionStyleDefault handler:^(MXCAlert *alert) {
                    weakSelf.actionMenu = nil;
                }];
                [weakSelf.actionMenu addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                    textField.secureTextEntry = NO;
                    textField.placeholder = @"ex: @bob:homeserver";
                }];
                [weakSelf.actionMenu addActionWithTitle:@"Invite" style:MXCAlertActionStyleDefault handler:^(MXCAlert *alert) {
                    UITextField *textField = [alert textFieldAtIndex:0];
                    NSString *userId = textField.text;
                    weakSelf.actionMenu = nil;
                    if (userId.length) {
                        [weakSelf.mxRoom inviteUser:userId success:^{
                            
                        } failure:^(NSError *error) {
                            NSLog(@"Invite %@ failed: %@", userId, error);
                            //Alert user
                            [[AppDelegate theDelegate] showErrorAsAlert:error];
                        }];
                    }
                }];
                [weakSelf.actionMenu showInViewController:weakSelf];
            }
        }];
        self.actionMenu.cancelButtonIndex = [self.actionMenu addActionWithTitle:@"Cancel" style:MXCAlertActionStyleDefault handler:^(MXCAlert *alert) {
            weakSelf.actionMenu = nil;
        }];
        weakSelf.actionMenu.sourceView = weakSelf.optionBtn;
        [self.actionMenu showInViewController:self];
    }
}

- (IBAction)showHideDateTime:(id)sender {
    if (dateFormatter) {
        // dateTime will be hidden
        dateFormatter = nil;
    } else {
        // dateTime will be visible
        NSString *dateFormat = @"MMM dd HH:mm";
        dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:[[[NSBundle mainBundle] preferredLocalizations] objectAtIndex:0]]];
        [dateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
        [dateFormatter setTimeStyle:NSDateFormatterNoStyle];
        [dateFormatter setDateFormat:dateFormat];
    }
    
    [self.messagesTableView reloadData];
}

- (IBAction)showHideRoomMembers:(id)sender {
    // Check whether the members list is displayed
    if (members) {
        [self hideRoomMembers];
    } else {
        [self hideAttachmentView];
        [self showRoomMembers];
    }
}

- (IBAction)onResendToggle:(id)sender {
    // sanity check
    if ([sender isKindOfClass:[UIButton class]]) {
        id hiddenLabel = [(UIButton*)sender viewWithTag:HIDDEN_UNSENT_MSG_LABEL];
        
        // get the hidden label where the event ID is store
        if ([hiddenLabel isKindOfClass:[UILabel class]]) {
            NSString* eventID =((UILabel*)hiddenLabel).text;
            
            // search the selected cell
            UIView* cellView = sender;
            while (![cellView isKindOfClass:[RoomMessageTableCell class]]) {
                cellView = cellView.superview;
            }
            
            if (cellView) {
                RoomMessage* roomMessage = ((RoomMessageTableCell*)cellView).message;
                RoomMessageComponent* component = [roomMessage componentWithEventId:eventID];
                
                // sanity check
                if (component) {
                    NSString* textMessage = component.textMessage;
                    
                    __weak typeof(self) weakSelf = self;
                    
                    self.actionMenu = [[MXCAlert alloc] initWithTitle:@"Resend the message"
                                                                 message:(roomMessage.messageType == RoomMessageTypeText) ? textMessage : nil
                                                                   style:MXCAlertStyleAlert];
                    
                    
                    self.actionMenu.cancelButtonIndex = [self.actionMenu addActionWithTitle:@"Cancel"
                                                                                      style:MXCAlertActionStyleDefault
                                                                                    handler:^(MXCAlert *alert) {
                                                                                        weakSelf.actionMenu = nil;
                                                                                    }];
                    [self.actionMenu addActionWithTitle:@"OK"
                                                  style:MXCAlertActionStyleDefault
                                                handler:^(MXCAlert *alert) {
                                                    weakSelf.actionMenu = nil;
                                                    
                                                    if (roomMessage.messageType == RoomMessageTypeText) {
                                                        // remove the message
                                                        [roomMessage removeEvent:eventID];
                                                        if (!roomMessage.components.count) {
                                                            @synchronized(weakSelf) {
                                                                [weakSelf.messages removeObject:roomMessage];
                                                            }
                                                        }
                                                        
                                                        [weakSelf sendTextMessage:textMessage];
                                                    } else if (roomMessage.messageType == RoomMessageTypeImage) {
                                                        // check if the message is still in the list
                                                        NSUInteger index;
                                                        @synchronized(weakSelf) {
                                                            index = [weakSelf.messages indexOfObject:roomMessage];
                                                            if (index != NSNotFound) {
                                                                [weakSelf.messages removeObjectAtIndex:index];
                                                            }
                                                        }
                                                        
                                                        if (index != NSNotFound) {
                                                            UIImage* image = [MediaManager loadCachePictureForURL:roomMessage.attachmentURL inFolder:weakSelf.roomId];
                                                            
                                                            // if the URL is still a local one
                                                            if (image) {
                                                                // it should mean that the media upload fails
                                                                [weakSelf sendImage:image];
                                                            } else if (roomMessage.attachmentURL.length > 0) {
                                                                // build the image dict
                                                                NSMutableDictionary* imageMessage = [[NSMutableDictionary alloc] init];
                                                                [imageMessage setObject:@"Image" forKey:@"body"];
                                                                [imageMessage setObject:roomMessage.attachmentInfo forKey:@"info"];
                                                                [imageMessage setObject:kMXMessageTypeImage forKey:@"msgtype"];
                                                                [imageMessage setObject:roomMessage.attachmentURL forKey:@"url"];
                                                                
                                                                if (roomMessage.previewURL) {
                                                                    [imageMessage setObject:roomMessage.previewURL forKey:kRoomMessageLocalPreviewKey];
                                                                }
                                                                
                                                                // send it again
                                                                [weakSelf sendMessage:imageMessage withLocalEvent:nil];
                                                            }
                                                        }
                                                    } else if (roomMessage.messageType == RoomMessageTypeVideo) {
                                                        // check if the message is still in the list
                                                        NSUInteger index;
                                                        @synchronized(weakSelf) {
                                                            index = [weakSelf.messages indexOfObject:roomMessage];
                                                            if (index != NSNotFound) {
                                                                [weakSelf.messages removeObjectAtIndex:index];
                                                            }
                                                        }
                                                        
                                                        if (index != NSNotFound) {
                                                            // if the URL is still a local one
                                                            if (![NSURL URLWithString:roomMessage.thumbnailURL].scheme) {
                                                                UIImage* image = [MediaManager loadCachePictureForURL:roomMessage.thumbnailURL inFolder:weakSelf.roomId];
                                                                // it should mean that the thumbnail upload fails
                                                                [weakSelf sendVideo:[NSURL fileURLWithPath:roomMessage.attachmentURL]  withThumbnail:image];
                                                            } else {
                                                                
                                                                NSMutableDictionary* videoMessage = [[NSMutableDictionary alloc] init];
                                                                [videoMessage setObject:@"Video" forKey:@"body"];
                                                                [videoMessage setObject:roomMessage.attachmentInfo forKey:@"info"];
                                                                [videoMessage setObject:kMXMessageTypeVideo forKey:@"msgtype"];
                                                                [videoMessage setObject:roomMessage.attachmentURL forKey:@"url"];
                                                                
                                                                if (roomMessage.previewURL) {
                                                                    [videoMessage setObject:roomMessage.previewURL forKey:kRoomMessageLocalPreviewKey];
                                                                }
                                                                
                                                                // the attachment is still a local path
                                                                if (![NSURL URLWithString:roomMessage.attachmentURL].scheme) {
                                                                    // Add a new local event
                                                                    MXEvent* localEvent = [weakSelf createLocalEchoEventWithoutContent];
                                                                    localEvent.content = videoMessage;
                                                                    [weakSelf addLocalEchoEvent:localEvent];
                                                                    [weakSelf sendVideoContent:videoMessage localEvent:localEvent];
                                                                } else {
                                                                    // set localEvent to nil to avoid useless search
                                                                    [weakSelf sendMessage:videoMessage withLocalEvent:nil];
                                                                }
                                                            }
                                                        }
                                                    }
                                                    
                                                }];
                    
                    [self.actionMenu showInViewController:[[AppDelegate theDelegate].masterTabBarController selectedViewController]];
                }
            }
        }
    }
}

#pragma mark - Post messages

- (void)sendMessage:(NSDictionary*)msgContent withLocalEvent:(MXEvent*)localEvent {
    MXMessageType msgType = msgContent[@"msgtype"];
    if (msgType) {
        // Check whether a temporary event has already been added for local echo (this happens on attachments)
        if (localEvent) {
            // Look for this local event in messages
            RoomMessage *message = [self messageWithEventId:localEvent.eventId];
            if (message) {
                // Update the local event with the actual msg content
                localEvent.content = msgContent;
                if (message.thumbnailURL) {
                    // Reuse the current thumbnailURL as preview
                    [localEvent.content setValue:message.thumbnailURL forKey:kRoomMessageLocalPreviewKey];
                }
                
                if (message.messageType == RoomMessageTypeText) {
                    [message removeEvent:localEvent.eventId];
                    [message addEvent:localEvent withRoomState:self.mxRoom.state];
                    if (!message.components.count) {
                        [self removeMessage:message];
                    }
                } else {
                    // Create a new message
                    RoomMessage *aNewMessage = [[RoomMessage alloc] initWithEvent:localEvent andRoomState:self.mxRoom.state];
                    if (aNewMessage) {
                        [self replaceMessage:message withMessage:aNewMessage];
                    } else {
                        [self removeMessage:message];
                    }
                }
            }
            
            [self.messagesTableView reloadData];
        } else {
            // Add a new local event
            localEvent = [self createLocalEchoEventWithoutContent];
            localEvent.content = msgContent;
            [self addLocalEchoEvent:localEvent];
        }
        
        // Send message to the room
        [self.mxRoom sendMessageOfType:msgType content:msgContent success:^(NSString *eventId) {
            // Switch on processing queue
            dispatch_async([MatrixSDKHandler sharedHandler].processingQueue, ^{
                // Check whether the event is still pending (It may be received from event stream)
                NSUInteger index;
                MXEvent *pendingEvent = nil;
                @synchronized(self) {
                    for (index = 0; index < pendingOutgoingEvents.count; index++) {
                        pendingEvent = [pendingOutgoingEvents objectAtIndex:index];
                        if ([pendingEvent.eventId isEqualToString:localEvent.eventId]) {
                            // This event is not pending anymore
                            [pendingOutgoingEvents removeObjectAtIndex:index];
                            break;
                        }
                        pendingEvent = nil;
                    }
                }
                
                if (pendingEvent) {
                    // Replace the local event id in the related message
                    RoomMessage *message = [self messageWithEventId:localEvent.eventId];
                    if (message) {
                        [message replaceLocalEventId:localEvent.eventId withEventId:eventId];
                    }
                    
                    // Note: Messages table will be refreshed for this outgoing event on event stream notification (see messagesListener)
                }
            });
        } failure:^(NSError *error) {
            // Switch on processing queue to serialize this operation with the message handling
            dispatch_async([MatrixSDKHandler sharedHandler].processingQueue, ^{
                // Check whether the event is still pending (It may be received from event stream)
                NSUInteger index;
                MXEvent *pendingEvent = nil;
                @synchronized (self) {
                    for (index = 0; index < pendingOutgoingEvents.count; index++) {
                        pendingEvent = [pendingOutgoingEvents objectAtIndex:index];
                        if ([pendingEvent.eventId isEqualToString:localEvent.eventId]) {
                            // This event is not pending anymore
                            [pendingOutgoingEvents removeObjectAtIndex:index];
                            break;
                        }
                        pendingEvent = nil;
                    }
                }
                
                if (pendingEvent) {
                    // Handle error
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self handleError:error forLocalEvent:localEvent];
                    });
                }
            });
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
    NSString *localEventId = [NSString stringWithFormat:@"%@%@", kLocalEchoEventIdPrefix, [[NSProcessInfo processInfo] globallyUniqueString]];
    MXEvent *localEvent = [[MXEvent alloc] init];
    localEvent.roomId = self.roomId;
    localEvent.eventId = localEventId;
    localEvent.eventType = MXEventTypeRoomMessage;
    localEvent.type = kMXEventTypeStringRoomMessage;
    localEvent.originServerTs = (uint64_t) ([[NSDate date] timeIntervalSince1970] * 1000);
    
    localEvent.userId = [MatrixSDKHandler sharedHandler].userId;
    return localEvent;
}

- (void)addLocalEchoEvent:(MXEvent*)mxEvent {
    // Check whether this new event may be grouped with last message
    RoomMessage *lastMessage;
    @synchronized (self) {
        lastMessage = [messages lastObject];
    }
    
    if (lastMessage == nil || [lastMessage addEvent:mxEvent withRoomState:self.mxRoom.state] == NO) {
        // Create a new RoomMessage
        lastMessage = [[RoomMessage alloc] initWithEvent:mxEvent andRoomState:self.mxRoom.state];
        if (lastMessage) {
            @synchronized (self) {
                [messages addObject:lastMessage];
            }
        } else {
            lastMessage = nil;
            NSLog(@"ERROR: Unable to add local event: %@", mxEvent.description);
        }
    }
    
    if (lastMessage) {
        @synchronized (self) {
            // Report this event as pending one
            [pendingOutgoingEvents addObject:mxEvent];
        }
        
        // Refresh table display
        [self.messagesTableView reloadData];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self scrollToBottomAnimated:NO];
        });
    }
}

- (NSData*)cachedImageData:(UIImage*)image withURL:(NSString*)url {
    NSData *imageData = UIImageJPEGRepresentation(image, 0.8);
    NSString *cacheFilePath = [MediaManager cacheMediaData:imageData forURL:url andType:@"image/jpeg" inFolder:self.roomId];
    if (cacheFilePath) {
        if (tmpCachedAttachments == nil) {
            tmpCachedAttachments = [NSMutableArray array];
        }
        [tmpCachedAttachments addObject:cacheFilePath];
    }
    
    return imageData;
}

- (MXEvent*)addLocalEchoEventForAttachedImage:(UIImage*)image {
    // Create new item
    MXEvent *localEvent = [self createLocalEchoEventWithoutContent];
    // We store temporarily the image in cache, use the localId to build temporary url
    NSString *dummyURL = [NSString stringWithFormat:@"%@%@", kMediaManagerPrefixForDummyURL, localEvent.eventId];
    NSData* imageData = [self cachedImageData:image withURL:dummyURL];
    
    // Prepare event content
    NSMutableDictionary *info = [[NSMutableDictionary alloc] init];
    [info setValue:@"image/jpeg" forKey:@"mimetype"];
    [info setValue:[NSNumber numberWithUnsignedInteger:(NSUInteger)image.size.width] forKey:@"w"];
    [info setValue:[NSNumber numberWithUnsignedInteger:(NSUInteger)image.size.height] forKey:@"h"];
    [info setValue:[NSNumber numberWithUnsignedInteger:imageData.length] forKey:@"size"];
    localEvent.content = @{@"msgtype":kMXMessageTypeImage, @"url":dummyURL, @"info":info, kRoomMessageUploadIdKey:localEvent.eventId};
    // Note: we have defined here an upload id with the local event id
    
    // Add this new event
    [self addLocalEchoEvent:localEvent];
    return localEvent;
}

- (MXEvent*)addLocalEchoEventForAttachedVideo:(UIImage*)thumbnail videoPath:(NSString*)videoPath {
    // Create new item
    MXEvent *localEvent = [self createLocalEchoEventWithoutContent];
    NSString *dummyURL = [NSString stringWithFormat:@"%@%@", kMediaManagerPrefixForDummyURL, localEvent.eventId];
    NSData* imageData = [self cachedImageData:thumbnail withURL:dummyURL];
    
    NSMutableDictionary* content = [[NSMutableDictionary alloc] init];
    
    [content setObject:kMXMessageTypeVideo forKey:@"msgtype"];
    [content setObject:videoPath forKey:@"url"];
    
    // thumbnail
    NSMutableDictionary *thumbnail_info = [[NSMutableDictionary alloc] init];
    [thumbnail_info setValue:@"image/jpeg" forKey:@"mimetype"];
    [thumbnail_info setValue:[NSNumber numberWithUnsignedInteger:(NSUInteger)thumbnail.size.width] forKey:@"w"];
    [thumbnail_info setValue:[NSNumber numberWithUnsignedInteger:(NSUInteger)thumbnail.size.height] forKey:@"h"];
    [thumbnail_info setValue:[NSNumber numberWithUnsignedInteger:imageData.length] forKey:@"size"];
    
    NSMutableDictionary* attachmentInfo = [[NSMutableDictionary alloc] init];
    [attachmentInfo setValue:dummyURL forKey:@"thumbnail_url"];
    [attachmentInfo setValue:thumbnail_info forKey:@"thumbnail_info"];
    
    [content setObject:attachmentInfo forKey:@"info"];
    [content setObject:localEvent.eventId forKey:kRoomMessageUploadIdKey];
    
    localEvent.content = content;
    
    // Add this new event
    [self addLocalEchoEvent:localEvent];
    return localEvent;
}

- (void)handleError:(NSError *)error forLocalEvent:(MXEvent *)localEvent {
    NSLog(@"Post message failed: %@", error);
    if (error) {
        // Alert user
        [[AppDelegate theDelegate] showErrorAsAlert:error];
    }
    
    dispatch_async([MatrixSDKHandler sharedHandler].processingQueue, ^{
        // Update the temporary event with this local event id
        RoomMessage *message = [self messageWithEventId:localEvent.eventId];
        if (message) {
            NSLog(@"Posted event: %@", localEvent.description);
            NSString *failedEventId = [NSString stringWithFormat:@"%@%lld", kFailedEventIdPrefix, (long long)(CFAbsoluteTimeGetCurrent() * 1000)];
            [message replaceLocalEventId:localEvent.eventId withEventId:failedEventId];
        }
        
        // Reload on the right thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.messagesTableView reloadData];
        });
    });
}

- (MXEvent*)pendingEventRelatedToEvent:(MXEvent*)mxEvent {
    // Note: mxEvent is supposed here to be an outgoing event received from event stream.
    // This method returns a pending event (if any) whose content matches with received event content.
    NSString *msgtype = mxEvent.content[@"msgtype"];
    
    MXEvent *pendingEvent = nil;
    @synchronized(self) {
        for (NSInteger index = 0; index < pendingOutgoingEvents.count; index++) {
            pendingEvent = [pendingOutgoingEvents objectAtIndex:index];
            NSString *pendingEventType = pendingEvent.content[@"msgtype"];
            
            if ([msgtype isEqualToString:pendingEventType]) {
                if ([msgtype isEqualToString:kMXMessageTypeText] || [msgtype isEqualToString:kMXMessageTypeEmote]) {
                    // Compare content body
                    if ([mxEvent.content[@"body"] isEqualToString:pendingEvent.content[@"body"]]) {
                        break;
                    }
                } else if ([msgtype isEqualToString:kMXMessageTypeLocation]) {
                    // Compare geo uri
                    if ([mxEvent.content[@"geo_uri"] isEqualToString:pendingEvent.content[@"geo_uri"]]) {
                        break;
                    }
                } else {
                    // Here the type is kMXMessageTypeImage, kMXMessageTypeAudio or kMXMessageTypeVideo
                    if ([mxEvent.content[@"url"] isEqualToString:pendingEvent.content[@"url"]]) {
                        break;
                    }
                }
            }
            pendingEvent = nil;
        }
    }
    
    return pendingEvent;
}

- (BOOL)isIRCStyleCommand:(NSString*)text{
    // Check whether the provided text may be an IRC-style command
    if ([text hasPrefix:@"/"] == NO || [text hasPrefix:@"//"] == YES) {
        return NO;
    }
    
    // Parse command line
    NSArray *components = [text componentsSeparatedByString:@" "];
    NSString *cmd = [components objectAtIndex:0];
    NSUInteger index = 1;
    
    if ([cmd isEqualToString:kCmdEmote]) {
        // send message as an emote
        [self sendTextMessage:text];
    } else if ([text hasPrefix:kCmdChangeDisplayName]) {
        // Change display name
        NSString *displayName = [text substringFromIndex:kCmdChangeDisplayName.length + 1];
        // Remove white space from both ends
        displayName = [displayName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        
        if (displayName.length) {
            MatrixSDKHandler *mxHandler = [MatrixSDKHandler sharedHandler];
            [mxHandler.mxRestClient setDisplayName:displayName success:^{
            } failure:^(NSError *error) {
                NSLog(@"Set displayName failed: %@", error);
                //Alert user
                [[AppDelegate theDelegate] showErrorAsAlert:error];
            }];
        } else {
            // Display cmd usage in text input as placeholder
            self.messageTextView.placeholder = @"Usage: /nick <display_name>";
        }
    } else if ([text hasPrefix:kCmdJoinRoom]) {
        // Join a room
        NSString *roomAlias = [text substringFromIndex:kCmdJoinRoom.length + 1];
        // Remove white space from both ends
        roomAlias = [roomAlias stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        
        // Check
        if (roomAlias.length) {
            [[MatrixSDKHandler sharedHandler].mxSession joinRoom:roomAlias success:^(MXRoom *room) {
                // Show the room
                [[AppDelegate theDelegate].masterTabBarController showRoom:room.state.roomId];
            } failure:^(NSError *error) {
                NSLog(@"Join roomAlias (%@) failed: %@", roomAlias, error);
                //Alert user
                [[AppDelegate theDelegate] showErrorAsAlert:error];
            }];
        } else {
            // Display cmd usage in text input as placeholder
            self.messageTextView.placeholder = @"Usage: /join <room_alias>";
        }
    } else {
        // Retrieve userId
        NSString *userId = nil;
        while (index < components.count) {
            userId = [components objectAtIndex:index++];
            if (userId.length) {
                // done
                break;
            }
            // reset
            userId = nil;
        }
        
        if ([cmd isEqualToString:kCmdKickUser]) {
            if (userId) {
                // Retrieve potential reason
                NSString *reason = nil;
                while (index < components.count) {
                    if (reason) {
                        reason = [NSString stringWithFormat:@"%@ %@", reason, [components objectAtIndex:index++]];
                    } else {
                        reason = [components objectAtIndex:index++];
                    }
                }
                // Kick the user
                [self.mxRoom kickUser:userId reason:reason success:^{
                } failure:^(NSError *error) {
                    NSLog(@"Kick user (%@) failed: %@", userId, error);
                    //Alert user
                    [[AppDelegate theDelegate] showErrorAsAlert:error];
                }];
            } else {
                // Display cmd usage in text input as placeholder
                self.messageTextView.placeholder = @"Usage: /kick <userId> [<reason>]";
            }
        } else if ([cmd isEqualToString:kCmdBanUser]) {
            if (userId) {
                // Retrieve potential reason
                NSString *reason = nil;
                while (index < components.count) {
                    if (reason) {
                        reason = [NSString stringWithFormat:@"%@ %@", reason, [components objectAtIndex:index++]];
                    } else {
                        reason = [components objectAtIndex:index++];
                    }
                }
                // Ban the user
                [self.mxRoom banUser:userId reason:reason success:^{
                } failure:^(NSError *error) {
                    NSLog(@"Ban user (%@) failed: %@", userId, error);
                    //Alert user
                    [[AppDelegate theDelegate] showErrorAsAlert:error];
                }];
            } else {
                // Display cmd usage in text input as placeholder
                self.messageTextView.placeholder = @"Usage: /ban <userId> [<reason>]";
            }
        } else if ([cmd isEqualToString:kCmdUnbanUser]) {
            if (userId) {
                // Unban the user
                [self.mxRoom unbanUser:userId success:^{
                } failure:^(NSError *error) {
                    NSLog(@"Unban user (%@) failed: %@", userId, error);
                    //Alert user
                    [[AppDelegate theDelegate] showErrorAsAlert:error];
                }];
            } else {
                // Display cmd usage in text input as placeholder
                self.messageTextView.placeholder = @"Usage: /unban <userId>";
            }
        } else if ([cmd isEqualToString:kCmdSetUserPowerLevel]) {
            // Retrieve power level
            NSString *powerLevel = nil;
            while (index < components.count) {
                powerLevel = [components objectAtIndex:index++];
                if (powerLevel.length) {
                    // done
                    break;
                }
                // reset
                powerLevel = nil;
            }
            // Set power level
            if (userId && powerLevel) {
                // Set user power level
                [self.mxRoom setPowerLevelOfUserWithUserID:userId powerLevel:[powerLevel integerValue] success:^{
                } failure:^(NSError *error) {
                    NSLog(@"Set user power (%@) failed: %@", userId, error);
                    //Alert user
                    [[AppDelegate theDelegate] showErrorAsAlert:error];
                }];
            } else {
                // Display cmd usage in text input as placeholder
                self.messageTextView.placeholder = @"Usage: /op <userId> <power level>";
            }
        } else if ([cmd isEqualToString:kCmdResetUserPowerLevel]) {
            if (userId) {
                // Reset user power level
                [self.mxRoom setPowerLevelOfUserWithUserID:userId powerLevel:0 success:^{
                } failure:^(NSError *error) {
                    NSLog(@"Reset user power (%@) failed: %@", userId, error);
                    //Alert user
                    [[AppDelegate theDelegate] showErrorAsAlert:error];
                }];
            } else {
                // Display cmd usage in text input as placeholder
                self.messageTextView.placeholder = @"Usage: /deop <userId>";
            }
        } else {
            NSLog(@"Unrecognised IRC-style command: %@", text);
            self.messageTextView.placeholder = [NSString stringWithFormat:@"Unrecognised IRC-style command: %@", cmd];
        }
    }
    return YES;
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
        NSTimeInterval timerTimeout = ROOMVIEWCONTROLLER_TYPING_TIMEOUT_SEC;
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
            notificationTimeoutMS = 2000 * ROOMVIEWCONTROLLER_TYPING_TIMEOUT_SEC;
        } else {
            // This typing event is too old, we will ignore it
            typing = NO;
            NSLog(@"sendTypingNotification: a typing event has been ignored");
        }
    } else {
        // Cancel any typing timer
        [typingTimer invalidate];
        typingTimer = nil;
        // Reset last typing date
        lastTypingDate = nil;
    }
    
    // Send typing notification to server
    [self.mxRoom sendTypingNotification:typing
                                timeout:notificationTimeoutMS
                                success:^{
                                    // Reset last typing date
                                    lastTypingDate = nil;
                                } failure:^(NSError *error) {
                                    NSLog(@"sendTypingNotification (%d) failed: %@", typing, error);
                                    // Cancel timer (if any)
                                    [typingTimer invalidate];
                                    typingTimer = nil;
                                    // Send again
                                    [self handleTypingNotification:typing];
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


# pragma mark - UIImagePickerControllerDelegate

- (void)sendImage:(UIImage*)image {
    // Add a temporary event while the image is attached (local echo)
    MXEvent *localEvent = [self addLocalEchoEventForAttachedImage:image];
    
    // use the generated info dict to retrieve useful data
    NSMutableDictionary *infoDict = [localEvent.content valueForKey:@"info"];
    NSData *imageData = [NSData dataWithContentsOfFile:[MediaManager cachePathForMediaURL:[localEvent.content valueForKey:@"url"] andType:[infoDict objectForKey:@"mimetype"] inFolder:self.roomId]];
    
    // Upload data
    MediaLoader *mediaLoader = [MediaManager prepareUploaderWithId:localEvent.eventId initialRange:0 andRange:1.0 inFolder:self.roomId];
    [mediaLoader uploadData:imageData mimeType:[infoDict objectForKey:@"mimetype"] success:^(NSString *url) {
        [MediaManager removeUploaderWithId:localEvent.eventId inFolder:self.roomId];
        
        NSMutableDictionary *imageMessage = [[NSMutableDictionary alloc] init];
        [imageMessage setValue:kMXMessageTypeImage forKey:@"msgtype"];
        [imageMessage setValue:url forKey:@"url"];
        [imageMessage setValue:infoDict forKey:@"info"];
        [imageMessage setValue:@"Image" forKey:@"body"];
        // Send message for this attachment
        [self sendMessage:imageMessage withLocalEvent:localEvent];
    } failure:^(NSError *error) {
        // check if the upload is still defined
        // it could have been cancelled with an external events
        if ([MediaManager existingUploaderWithId:localEvent.eventId inFolder:self.roomId])
        {
            [MediaManager removeUploaderWithId:localEvent.eventId inFolder:self.roomId];
            NSLog(@"Failed to upload image: %@", error);
            [self handleError:error forLocalEvent:localEvent];
        }
    }];
}

- (void)dismissAttachmentImageViews {
    if (self.imageValidationView) {
        [self.imageValidationView dismissSelection];
        [self.imageValidationView removeFromSuperview];
        self.imageValidationView = nil;
    }
    
    if (highResImageView) {
        [highResImageView removeFromSuperview];
        highResImageView = nil;
    }
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    
    // Set visible room id
    [AppDelegate theDelegate].masterTabBarController.visibleRoomId = self.roomId;
    
    NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
    if ([mediaType isEqualToString:(NSString *)kUTTypeImage]) {
        UIImage *selectedImage = [info objectForKey:UIImagePickerControllerOriginalImage];
        if (selectedImage) {
            __weak typeof(self) weakSelf = self;
            
            // media picker does not offer a preview
            // so add a preview to let the user validates his selection
            if (picker.sourceType == UIImagePickerControllerSourceTypePhotoLibrary) {
                
                // wait that the media picker is dismissed to have the valid membersView frame
                // else it would include a status bar height offset
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.imageValidationView = [[MXCImageView alloc] initWithFrame:self.membersView.frame];
                    self.imageValidationView.stretchable = YES;
                    self.imageValidationView.fullScreen = YES;
                    self.imageValidationView.mediaFolder = self.roomId;
                    
                    // the user validates the image
                    [self.imageValidationView setRightButtonTitle:@"OK" handler:^(MXCImageView* imageView, NSString* buttonTitle) {
                        // dismiss the image view
                        [weakSelf dismissAttachmentImageViews];
                        
                        [weakSelf sendImage:selectedImage];
                    }];
                    
                    // the user wants to use an other image
                    [self.imageValidationView setLeftButtonTitle:@"Cancel" handler:^(MXCImageView* imageView, NSString* buttonTitle) {
                        
                        // dismiss the image view
                        [weakSelf dismissAttachmentImageViews];
                        
                        // Open again media gallery
                        UIImagePickerController *mediaPicker = [[UIImagePickerController alloc] init];
                        mediaPicker.delegate = weakSelf;
                        mediaPicker.sourceType = picker.sourceType;
                        mediaPicker.allowsEditing = NO;
                        mediaPicker.mediaTypes = [NSArray arrayWithObjects:(NSString *)kUTTypeImage, (NSString *)kUTTypeMovie, nil];
                        [[AppDelegate theDelegate].masterTabBarController presentMediaPicker:mediaPicker];
                    }];
                    
                    self.imageValidationView.image = selectedImage;
                });
            } else {
                [weakSelf sendImage:selectedImage];
            }
        }
    } else if ([mediaType isEqualToString:(NSString *)kUTTypeMovie]) {
        NSURL* selectedVideo = [info objectForKey:UIImagePickerControllerMediaURL];
        // Check the selected video, and ignore multiple calls (observed when user pressed several time Choose button)
        if (selectedVideo && !tmpVideoPlayer) {
            // Create video thumbnail
            tmpVideoPlayer = [[MPMoviePlayerController alloc] initWithContentURL:selectedVideo];
            if (tmpVideoPlayer) {
                [tmpVideoPlayer setShouldAutoplay:NO];
                [[NSNotificationCenter defaultCenter] addObserver:self
                                                         selector:@selector(moviePlayerThumbnailImageRequestDidFinishNotification:)
                                                             name:MPMoviePlayerThumbnailImageRequestDidFinishNotification
                                                           object:nil];
                [tmpVideoPlayer requestThumbnailImagesAtTimes:@[@1.0f] timeOption:MPMovieTimeOptionNearestKeyFrame];
                // We will finalize video attachment when thumbnail will be available (see movie player callback)
                return;
            }
        }
    }
    
    [self dismissMediaPicker];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self dismissMediaPicker];
}

- (void)dismissMediaPicker {
    [[AppDelegate theDelegate].masterTabBarController dismissMediaPicker];
}

#pragma mark - Segues

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([[segue identifier] isEqualToString:@"showMemberSheet"]) {
        MemberViewController* controller = [segue destinationViewController];
        
        if (selectedRoomMember) {
            controller.mxRoomMember = selectedRoomMember;
            selectedRoomMember = nil;
        } else {
            NSIndexPath *indexPath = [self.membersTableView indexPathForSelectedRow];
            controller.mxRoomMember = [members objectAtIndex:indexPath.row];
        }
        controller.mxRoom = self.mxRoom;
    }
}

@end


