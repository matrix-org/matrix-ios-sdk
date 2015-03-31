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

#import "MXKSampleJSQMessagesViewController.h"

#import "UIImageView+AFNetworking.h"

@interface MXKSampleJSQMessagesViewController () {
    /**
     The data source providing messages for the current room.
     */
    MXKSampleJSQRoomDataSource *roomDataSource;
    
    JSQMessagesBubbleImage *outgoingBubbleImageData;
    JSQMessagesBubbleImage *incomingBubbleImageData;

    /**
     The cache for initials avatars placeholders
     */
    NSMutableDictionary *membersPlaceHolderAvatar;
    
    UIImagePickerController *mediaPicker;
}

@end

@implementation MXKSampleJSQMessagesViewController

#pragma mark -

- (void)viewDidLoad {
    [super viewDidLoad];

    // Check whether a source has been defined
    if (roomDataSource) {
        [self configureView];
    }
}

- (void)dealloc {
    roomDataSource = nil;
    
    outgoingBubbleImageData = nil;
    incomingBubbleImageData = nil;
    
    membersPlaceHolderAvatar = nil;

    [[NSNotificationCenter defaultCenter] removeObserver:self name:MXSessionStateDidChangeNotification object:nil];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];

    // Dispose of any resources that can be recreated.
}

- (void)configureView {
    
    // Create message bubble images objects.
    JSQMessagesBubbleImageFactory *bubbleFactory = [[JSQMessagesBubbleImageFactory alloc] init];
    outgoingBubbleImageData = [bubbleFactory outgoingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleLightGrayColor]];
    incomingBubbleImageData = [bubbleFactory incomingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleGreenColor]];
    
    // Prepare avatars storage
    membersPlaceHolderAvatar = [NSMutableDictionary dictionary];
    
    // Start showing history right now
    [roomDataSource paginateBackMessagesToFillRect:self.view.frame success:^{
        // @TODO (hide loading wheel)
    } failure:^(NSError *error) {
        // @TODO
    }];
}

- (void)dismissMediaPicker {
    if (mediaPicker) {
        [self dismissViewControllerAnimated:NO completion:nil];
        mediaPicker.delegate = nil;
        mediaPicker = nil;
    }
}

#pragma mark -

- (void)displayRoom:(MXKSampleJSQRoomDataSource *)inRoomDataSource {
    roomDataSource = inRoomDataSource;
    roomDataSource.delegate = self;

    self.senderId = roomDataSource.mxSession.matrixRestClient.credentials.userId;
    if (roomDataSource.mxSession.myUser) {
        self.senderDisplayName = roomDataSource.mxSession.myUser.displayname;
    }
    else {
        // MXSession is not yet ready. Use sender id for now. It will be updated on didMXSessionStateChange:
        self.senderDisplayName = self.senderId;
    }

    if (self.collectionView) {
        [self configureView];
    }

    // Listen to MXSession state changes
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didMXSessionStateChange:) name:MXSessionStateDidChangeNotification object:nil];
}

#pragma mark - MXKDataSourceDelegate
- (void)dataSource:(MXKDataSource *)dataSource didChange:(id)changes {
    // For now, do a simple full reload
    [self.collectionView reloadData];
    [self.collectionView.collectionViewLayout invalidateLayout];

    // @TODO: Use this method only when receiving a message and the bottom of messages list is displayed
    //[self finishReceivingMessage];

    // Show "Load Earlier Messages" only if there are messages in the room
    self.showLoadEarlierMessagesHeader = YES;
}

#pragma mark - MXSessionStateDidChangeNotification
- (void)didMXSessionStateChange:(NSNotification *)notif {

    // Check this is our Matrix session that has changed
    if (notif.object == roomDataSource.mxSession) {

        // Display name is now available
        if (NO == [self.senderId isEqualToString:roomDataSource.mxSession.myUser.displayname]) {
            self.senderDisplayName = roomDataSource.mxSession.myUser.displayname;
            [self finishReceivingMessage];
        }
    }
}

#pragma mark - KVO
- (void) observeValueForKeyPath:(NSString *)path ofObject:(id) object change:(NSDictionary *) change context:(void *)context {

    // Check changes on cell.avatarImageView.image (registered by [self cellForItemAtIndexPath:])
    if ([path isEqualToString:@"image"]) {

        UIImageView *avatarImageView = (UIImageView*)object;
        if (avatarImageView.image) {

            // Avoid infinite loop
            [avatarImageView removeObserver:self forKeyPath:@"image"];

            // Make the image circular
            avatarImageView.image = [JSQMessagesAvatarImageFactory circularAvatarImage:avatarImageView.image withDiameter:kJSQMessagesCollectionViewAvatarSizeDefault];
        }
    }
}

#pragma mark - JSQMessages view controller

- (void)didPressSendButton:(UIButton *)button
           withMessageText:(NSString *)text
                  senderId:(NSString *)senderId
         senderDisplayName:(NSString *)senderDisplayName
                      date:(NSDate *)date
{
    if (!text.length) {
        return;
    }
    
    // Prevent multiple send requests
    button.enabled = NO;
    
    // Send message to the room
    [roomDataSource.room sendMessageOfType:kMXMessageTypeText content:@{@"body":text} success:^(NSString *eventId) {
        NSLog(@"Succeed to send text message");
        [self finishSendingMessage];
        button.enabled = YES;
    } failure:^(NSError *error) {
        NSLog(@"Failed to send text message (%@)", error);
        button.enabled = YES;
    }];
}

- (void)didPressAccessoryButton:(UIButton *)sender
{
    UIActionSheet *sheet = [[UIActionSheet alloc] initWithTitle:@"Media messages"
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                         destructiveButtonTitle:nil
                                              otherButtonTitles:@"Photo Library", @"Take Photo/Video", nil];
    
    [sheet showFromToolbar:self.inputToolbar];
}

#pragma mark - JSQMessages CollectionView DataSource

- (id<JSQMessageData>)collectionView:(JSQMessagesCollectionView *)collectionView messageDataForItemAtIndexPath:(NSIndexPath *)indexPath {
    
    return [roomDataSource collectionView:collectionView messageDataForItemAtIndexPath:indexPath];
}

- (id<JSQMessageBubbleImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView messageBubbleImageDataForItemAtIndexPath:(NSIndexPath *)indexPath {
    
    /**
     *  You may return nil here if you do not want bubbles.
     *  In this case, you should set the background color of your collection view cell's textView.
     *
     *  Otherwise, return your previously created bubble image data objects.
     */
    id<JSQMessageData> messageData = [self collectionView:collectionView messageDataForItemAtIndexPath:indexPath];
    
    if ([messageData.senderId isEqualToString:self.senderId]) {
        return outgoingBubbleImageData;
    }
    return incomingBubbleImageData;
}

- (id<JSQMessageAvatarImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView avatarImageDataForItemAtIndexPath:(NSIndexPath *)indexPath {
    
    /**
     *  Return `nil` here if you do not want avatars.
     *  If you do return `nil`, be sure to do the following in `viewDidLoad`:
     *
     *  self.collectionView.collectionViewLayout.incomingAvatarViewSize = CGSizeZero;
     *  self.collectionView.collectionViewLayout.outgoingAvatarViewSize = CGSizeZero;
     *
     *  It is possible to have only outgoing avatars or only incoming avatars, too.
     */
    
    /**
     *  Return your previously created avatar image data objects.
     *
     *  Note: these the avatars will be sized according to these values:
     *
     *  self.collectionView.collectionViewLayout.incomingAvatarViewSize
     *  self.collectionView.collectionViewLayout.outgoingAvatarViewSize
     *
     *  Override the defaults in `viewDidLoad`
     */
    
    id<JSQMessageData> messageData = [self collectionView:collectionView messageDataForItemAtIndexPath:indexPath];

    // Return a placeholder UIImage for the avatar here
    // The true avatar will be set during the call of [self cellForItemAtIndexPath:]
    // In this last method, the avatarImageView is created and we need it to set the avatar URL asynchronously.
    // Once the avatar image is loaded, the avatarImageView will automatically refresh.
    JSQMessagesAvatarImage *placeHolderAvatar = [membersPlaceHolderAvatar objectForKey:messageData.senderId];
    if (!placeHolderAvatar) {
        placeHolderAvatar = [JSQMessagesAvatarImageFactory avatarImageWithUserInitials:[messageData.senderId substringWithRange:NSMakeRange(1,2)]
                                                            backgroundColor:[UIColor colorWithWhite:0.85f alpha:1.0f]
                                                                  textColor:[UIColor colorWithWhite:0.60f alpha:1.0f]
                                                                       font:[UIFont systemFontOfSize:14.0f]
                                                                   diameter:kJSQMessagesCollectionViewAvatarSizeDefault];
        
        [membersPlaceHolderAvatar setObject:placeHolderAvatar forKey:messageData.senderId];
    }
    
    return placeHolderAvatar;
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath {
    
    /**
     *  This logic should be consistent with what you return from `heightForCellTopLabelAtIndexPath:`
     *  The other label text delegate methods should follow a similar pattern.
     *
     *  Show a timestamp for every 3rd message
     */
    if (indexPath.item % 3 == 0) {
        id<JSQMessageData> messageData = [self collectionView:collectionView messageDataForItemAtIndexPath:indexPath];
        return [[JSQMessagesTimestampFormatter sharedFormatter] attributedTimestampForDate:messageData.date];
    }

    return nil;
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForMessageBubbleTopLabelAtIndexPath:(NSIndexPath *)indexPath {
    
    id<JSQMessageData> messageData = [self collectionView:collectionView messageDataForItemAtIndexPath:indexPath];
    
    /**
     *  iOS7-style sender name labels
     */
    if ([messageData.senderId isEqualToString:self.senderId]) {
        return nil;
    }

    if (indexPath.item - 1 > 0) {
        NSIndexPath *previousIndexPath = [NSIndexPath  indexPathForItem:indexPath.item - 1 inSection:indexPath.section];
        id<JSQMessageData> previousMessageData = [self collectionView:collectionView messageDataForItemAtIndexPath:previousIndexPath];

        if ([previousMessageData.senderId isEqualToString:messageData.senderId]) {
            return nil;
        }
    }

    /**
     *  Don't specify attributes to use the defaults.
     */
    return [[NSAttributedString alloc] initWithString:messageData.senderDisplayName];
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath {
    
    return nil;
}

#pragma mark - UICollectionView DataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    
    return [roomDataSource collectionView:collectionView numberOfItemsInSection:section];
}

- (UICollectionViewCell *)collectionView:(JSQMessagesCollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    
    /**
     *  Override point for customizing cells
     */
    JSQMessagesCollectionViewCell *cell = (JSQMessagesCollectionViewCell *)[super collectionView:collectionView cellForItemAtIndexPath:indexPath];
    
    /**
     *  Configure almost *anything* on the cell
     *
     *  Text colors, label text, label colors, etc.
     *
     *
     *  DO NOT set `cell.textView.font` !
     *  Instead, you need to set `self.collectionView.collectionViewLayout.messageBubbleFont` to the font you want in `viewDidLoad`
     *
     *
     *  DO NOT manipulate cell layout information!
     *  Instead, override the properties you want on `self.collectionView.collectionViewLayout` from `viewDidLoad`
     */
    
    id<JSQMessageData> messageData = [self collectionView:collectionView messageDataForItemAtIndexPath:indexPath];
    
    if (!messageData.isMediaMessage) {
        
        if ([messageData.senderId isEqualToString:self.senderId]) {
            cell.textView.textColor = [UIColor blackColor];
        }
        else {
            cell.textView.textColor = [UIColor whiteColor];
        }
        
        cell.textView.linkTextAttributes = @{ NSForegroundColorAttributeName : cell.textView.textColor,
                                              NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid) };
    }

    // Compute the member avatar URL
    MXRoomMember *roomMember = [roomDataSource.room.state memberWithUserId:messageData.senderId];

    NSString *avatarUrl = [roomDataSource.mxSession.matrixRestClient urlOfContentThumbnail:roomMember.avatarUrl withSize:CGSizeMake(kJSQMessagesCollectionViewAvatarSizeDefault, kJSQMessagesCollectionViewAvatarSizeDefault) andMethod:MXThumbnailingMethodCrop];
    if (!avatarUrl) {
        avatarUrl = roomMember.avatarUrl ;
    }

    // As the "square" image will be set asynchronously, register an observer on it in order to make it circular at runtime
    [cell.avatarImageView addObserver:self
                           forKeyPath:@"image"
                              options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
                              context:NULL];

    // Use the AFNetworking category to asynchronously load the image into the read-only avatarImageView
    // @TODO: Use the MXCMediaManager permanent cache. AFNetworking cache is just memory.
    // @TODO: This AFNetworking category does not detect multiple requests on the same URL.
    [cell.avatarImageView setImageWithURL:[NSURL URLWithString:avatarUrl]];

    return cell;
}

#pragma mark - JSQMessages collection view flow layout delegate

#pragma mark - Adjusting cell label heights

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    // Reuse the algo defined in the paired method
    if ([self collectionView:collectionView attributedTextForCellTopLabelAtIndexPath:indexPath]) {
        return kJSQMessagesCollectionViewCellLabelHeightDefault;
    }

    return 0.0f;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForMessageBubbleTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    // Reuse the algo defined in the paired method
    if ([self collectionView:collectionView attributedTextForMessageBubbleTopLabelAtIndexPath:indexPath]) {
        return kJSQMessagesCollectionViewCellLabelHeightDefault;
    }

    return 0.0f;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    return 0.0f;
}

#pragma mark - Responding to collection view tap events

- (void)collectionView:(JSQMessagesCollectionView *)collectionView
                header:(JSQMessagesLoadEarlierHeaderView *)headerView didTapLoadEarlierMessagesButton:(UIButton *)sender
{
    // Disable the button while requesting
    sender.enabled = NO;
    [roomDataSource paginateBackMessages:30 success:^{

        // Pagingate messages have been received by the didChange protocol
        // Just need  to reenable the button
        sender.enabled = YES;

    } failure:^(NSError *error) {
        sender.enabled= YES;
    }];
}

- (void)collectionView:(JSQMessagesCollectionView *)collectionView didTapAvatarImageView:(UIImageView *)avatarImageView atIndexPath:(NSIndexPath *)indexPath
{
    NSLog(@"Tapped avatar!");
}

- (void)collectionView:(JSQMessagesCollectionView *)collectionView didTapMessageBubbleAtIndexPath:(NSIndexPath *)indexPath
{
    NSLog(@"Tapped message bubble!");
}

- (void)collectionView:(JSQMessagesCollectionView *)collectionView didTapCellAtIndexPath:(NSIndexPath *)indexPath touchLocation:(CGPoint)touchLocation
{
    NSLog(@"Tapped cell at %@!", NSStringFromCGPoint(touchLocation));
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (buttonIndex == actionSheet.cancelButtonIndex) {
        return;
    }
    
    switch (buttonIndex) {
        case 0: {
            // Open media gallery
            mediaPicker = [[UIImagePickerController alloc] init];
            mediaPicker.delegate = self;
            mediaPicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
            mediaPicker.allowsEditing = NO;
            mediaPicker.mediaTypes = [NSArray arrayWithObjects:(NSString *)kUTTypeImage, (NSString *)kUTTypeMovie, nil];
            [self presentViewController:mediaPicker animated:YES completion:^{}];
            break;
        }
        case 1: {
            // Open Camera
            mediaPicker = [[UIImagePickerController alloc] init];
            mediaPicker.delegate = self;
            mediaPicker.sourceType = UIImagePickerControllerSourceTypeCamera;
            mediaPicker.allowsEditing = NO;
            mediaPicker.mediaTypes = [NSArray arrayWithObjects:(NSString *)kUTTypeImage, (NSString *)kUTTypeMovie, nil];
            [self presentViewController:mediaPicker animated:YES completion:^{}];
            break;
        }
    }
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {

    NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
    if ([mediaType isEqualToString:(NSString *)kUTTypeImage]) {
        UIImage *selectedImage = [info objectForKey:UIImagePickerControllerOriginalImage];
        if (selectedImage) {
            NSLog(@"An Image has been selected");
            [roomDataSource sendImage:selectedImage success:nil failure:^(NSError *error) {
                // @TODO
            }];
        }
    } else if ([mediaType isEqualToString:(NSString *)kUTTypeMovie]) {
        NSURL* selectedVideo = [info objectForKey:UIImagePickerControllerMediaURL];
        // Check the selected video, and ignore multiple calls (observed when user pressed several time Choose button)
        if (selectedVideo) {
            NSLog(@"A video has been selected");
            // TODO
//            [roomDataSource.room sendVideo:selectedVideo];
        }
    }
    
    [self dismissMediaPicker];
}

@end
