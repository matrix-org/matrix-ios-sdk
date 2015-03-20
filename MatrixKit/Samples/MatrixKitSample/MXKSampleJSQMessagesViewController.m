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

@interface MXKSampleJSQMessagesViewController () {
    /**
     The data source providing messages for the current room.
     */
    MXKSampleJSQRoomDataSource *roomDataSource;
    
    JSQMessagesBubbleImage *outgoingBubbleImageData;
    JSQMessagesBubbleImage *incomingBubbleImageData;
    
    NSMutableDictionary *membersAvatar;
    
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
    
    membersAvatar = nil;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];

    // Dispose of any resources that can be recreated.
}

- (void)configureView {
    self.senderId = roomDataSource.mxSession.myUser.userId;
    self.senderDisplayName = roomDataSource. mxSession.myUser.displayname;
    
    // Create message bubble images objects.
    JSQMessagesBubbleImageFactory *bubbleFactory = [[JSQMessagesBubbleImageFactory alloc] init];
    outgoingBubbleImageData = [bubbleFactory outgoingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleLightGrayColor]];
    incomingBubbleImageData = [bubbleFactory incomingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleGreenColor]];
    
    // Prepare avatars storage
    membersAvatar = [NSMutableDictionary dictionary];
    
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
    
    if (self.collectionView) {
        [self configureView];
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

#pragma mark - MXKDataSourceDelegate
- (void)dataSource:(MXKDataSource *)dataSource didChange:(id)changes {
    // For now, do a simple full reload
    [self finishReceivingMessage];
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
    
    JSQMessagesAvatarImage *avatar = [membersAvatar objectForKey:messageData.senderId];
    if (!avatar) {
        avatar = [JSQMessagesAvatarImageFactory avatarImageWithUserInitials:[messageData.senderId substringWithRange:NSMakeRange(1,2)]
                                                            backgroundColor:[UIColor colorWithWhite:0.85f alpha:1.0f]
                                                                  textColor:[UIColor colorWithWhite:0.60f alpha:1.0f]
                                                                       font:[UIFont systemFontOfSize:14.0f]
                                                                   diameter:kJSQMessagesCollectionViewAvatarSizeDefault];
        
        [membersAvatar setObject:avatar forKey:messageData.senderId];
    }
    
    return avatar;
}

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath {
    
    /**
     *  This logic should be consistent with what you return from `heightForCellTopLabelAtIndexPath:`
     *  The other label text delegate methods should follow a similar pattern.
     */
    
    // TODO: display date
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
    
    return cell;
}

#pragma mark - JSQMessages collection view flow layout delegate

#pragma mark - Adjusting cell label heights

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    /**
     *  Each label in a cell has a `height` delegate method that corresponds to its text dataSource method
     */
    
    /**
     *  This logic should be consistent with what you return from `attributedTextForCellTopLabelAtIndexPath:`
     *  The other label height delegate methods should follow similarly
     */
    
    // TODO: display date
    return 0.0f;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForMessageBubbleTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    /**
     *  iOS7-style sender name labels
     */
    id<JSQMessageData> messageData = [self collectionView:collectionView messageDataForItemAtIndexPath:indexPath];
    if ([messageData.senderId isEqualToString:self.senderId]) {
        return 0.0f;
    }
    
    return kJSQMessagesCollectionViewCellLabelHeightDefault;
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
    NSLog(@"Load earlier messages!");
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
    
    NSString *tmpMessage = nil;
    
    NSString *mediaType = [info objectForKey:UIImagePickerControllerMediaType];
    if ([mediaType isEqualToString:(NSString *)kUTTypeImage]) {
        UIImage *selectedImage = [info objectForKey:UIImagePickerControllerOriginalImage];
        if (selectedImage) {
            NSLog(@"An Image has been selected");
            // TODO
//            [roomDataSource.room sendImage:selectedImage];
            tmpMessage = @"attached Image";
        }
    } else if ([mediaType isEqualToString:(NSString *)kUTTypeMovie]) {
        NSURL* selectedVideo = [info objectForKey:UIImagePickerControllerMediaURL];
        // Check the selected video, and ignore multiple calls (observed when user pressed several time Choose button)
        if (selectedVideo) {
            NSLog(@"A video has been selected");
            // TODO
//            [roomDataSource.room sendVideo:selectedVideo];
            tmpMessage = @"attached Video";
        }
    }
    
    // Post a temporary message until attachments are supported
    if (tmpMessage) {
        [roomDataSource.room sendMessageOfType:kMXMessageTypeText content:@{@"body":tmpMessage} success:^(NSString *eventId) {
        } failure:^(NSError *error) {
        }];
    }
    
    [self dismissMediaPicker];
}

@end
