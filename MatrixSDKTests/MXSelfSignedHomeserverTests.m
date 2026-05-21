/*
 Copyright 2017 Vector Creations Ltd

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

#import <XCTest/XCTest.h>

#import "MatrixSDKTestsData.h"

#import "MXSession.h"
#import "MXMediaManager.h"
#import "MXSDKOptions.h"
#import "MXAllowedCertificates.h"


@interface MXSelfSignedHomeserverTests : XCTestCase
{
    MatrixSDKTestsData *matrixSDKTestsData;
}

@end

@implementation MXSelfSignedHomeserverTests

- (void)setUp
{
    [super setUp];

    matrixSDKTestsData = [[MatrixSDKTestsData alloc] init];
}

- (void)tearDown
{
    matrixSDKTestsData = nil;

    [super tearDown];
}

#if TARGET_OS_IPHONE
- (UIImage *)anImageWithSize:(CGSize)size
{
    // Create a "canvas" (image context) to draw in.
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);

    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return image;
}
#endif

- (void)testRegiter
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    __block BOOL certificateCheckAsked = NO;
    [matrixSDKTestsData getHttpsBobCredentials:self readyToTest:^{

        XCTAssert(certificateCheckAsked, @"We must have been asked to check the certificate");
        XCTAssertNotNil(matrixSDKTestsData.bobCredentials);

        XCTAssertNotNil(matrixSDKTestsData.bobCredentials.accessToken);
        XCTAssertNotNil(matrixSDKTestsData.bobCredentials.allowedCertificate);
        XCTAssertNil(matrixSDKTestsData.bobCredentials.ignoredCertificate);

        [expectation fulfill];

    } onUnrecognizedCertificateBlock:^BOOL(NSData *certificate) {
        certificateCheckAsked = YES;
        return YES;
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

- (void)testTrustedCertificate
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    [matrixSDKTestsData getHttpsBobCredentials:self readyToTest:^{

        MXRestClient *mxRestClient = [[MXRestClient alloc] initWithCredentials:matrixSDKTestsData.bobCredentials andOnUnrecognizedCertificateBlock:^BOOL(NSData *certificate) {

            XCTFail(@"We have already accepted the certificate. We should not be asked again");
            return NO;
        } andPersistentTokenDataHandler:nil andUnauthenticatedHandler:nil];

        [matrixSDKTestsData retain:mxRestClient];

        // Check the instance is usable
        XCTAssert(mxRestClient);
        [mxRestClient createRoom:nil visibility:0 roomAlias:nil topic:nil success:^(MXCreateRoomResponse *response) {

            [expectation fulfill];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];

    } onUnrecognizedCertificateBlock:^BOOL(NSData *certificate) {
        return YES;
    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

// Create a room and post a message to it
- (void)testRoomAndMessages
{
    [matrixSDKTestsData doHttpsMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        [mxSession createRoom:@"A room" visibility:0 roomAlias:nil topic:nil success:^(MXRoom *room) {

            XCTAssertNotNil(room);

            [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {
                [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    XCTAssertEqual(direction, MXTimelineDirectionForwards);
                    XCTAssert([event.description containsString:@"Hello"]);

                    [expectation fulfill];
                }];
            }];

            [room sendTextMessage:@"Hello" threadId:nil success:nil failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

// Create an e2e encrypted room and post a message to it
- (void)testE2ERoomAndMessages
{
    [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = YES;

    [matrixSDKTestsData doHttpsMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        [MXSDKOptions sharedInstance].enableCryptoWhenStartingMXSession = NO;

        [mxSession createRoom:@"A room" visibility:0 roomAlias:nil topic:nil success:^(MXRoom *room) {

            XCTAssertNotNil(room);

            [room enableEncryptionWithAlgorithm:kMXCryptoMegolmAlgorithm success:^{

                [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

                    [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                        XCTAssertEqual(direction, MXTimelineDirectionForwards);
                        XCTAssert(event.clearEvent);
                        XCTAssert([event.clearEvent.description containsString:@"Hello"]);

                        [expectation fulfill];
                    }];
                }];

                [room sendTextMessage:@"Hello" threadId:nil success:nil failure:^(NSError *error) {
                    XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                    [expectation fulfill];
                }];

            } failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}

#if TARGET_OS_IPHONE
// Create a room and upload an image
- (void)testRoomAndMedia
{
    [matrixSDKTestsData doHttpsMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        [mxSession createRoom:@"A room" visibility:0 roomAlias:nil topic:nil success:^(MXRoom *room) {

            XCTAssertNotNil(room);

            [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

                [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    XCTAssertEqual(direction, MXTimelineDirectionForwards);
                    XCTAssertEqualObjects(event.content[kMXMessageTypeKey], kMXMessageTypeImage);

                    NSString *contentURL = event.content[@"url"];
                    XCTAssert(contentURL);

                    // Download back the image
                    [mxSession.mediaManager downloadMediaFromMatrixContentURI:contentURL
                                                                     withType:nil
                                                                     inFolder:nil
                                                                      success:^(NSString *outputFilePath) {
                                                                          [expectation fulfill];
                                                                      } failure:^(NSError *error) {
                                                                          XCTFail(@"The request should not fail - NSError: %@", error);
                                                                          [expectation fulfill];
                                                                      }];
                }];
            }];

            CGSize size = CGSizeMake(100, 100);
            UIImage *image = [self anImageWithSize:size];

            [room sendImage:UIImagePNGRepresentation(image) withImageSize:size mimeType:@"image/png" andThumbnail:nil threadId:nil localEcho:nil success:nil failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}
#endif

- (void)testNotTrustedCertificate
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"asyncTest"];

    MXRestClient *mxRestClient = [[MXRestClient alloc] initWithHomeServer:kMXTestsHomeServerHttpsURL
                                        andOnUnrecognizedCertificateBlock:nil];

    [mxRestClient publicRoomsOnServer:nil limit:-1 since:nil filter:nil thirdPartyInstanceId:nil includeAllNetworks:NO success:^(MXPublicRoomsResponse *publicRoomsResponse) {

        XCTFail(@"The operation must fail because the self-signed certficate was not trusted");
        [expectation fulfill];

    } failure:^(NSError *error) {

        [expectation fulfill];

    }];

    [self waitForExpectationsWithTimeout:10 handler:nil];
}

#if TARGET_OS_IPHONE
- (void)testMediaWithNotTrustedCertificate
{
    // First, upload an image to our self-signed hs
    [matrixSDKTestsData doHttpsMXSessionTestWithBob:self readyToTest:^(MXSession *mxSession, XCTestExpectation *expectation) {

        [mxSession createRoom:@"A room" visibility:0 roomAlias:nil topic:nil success:^(MXRoom *room) {

            XCTAssertNotNil(room);

            [room liveTimeline:^(id<MXEventTimeline> liveTimeline) {

                [liveTimeline listenToEventsOfTypes:@[kMXEventTypeStringRoomMessage] onEvent:^(MXEvent *event, MXTimelineDirection direction, MXRoomState *roomState) {

                    XCTAssertEqual(direction, MXTimelineDirectionForwards);
                    XCTAssertEqualObjects(event.content[kMXMessageTypeKey], kMXMessageTypeImage);

                    NSString *contentURL = event.content[@"url"];
                    XCTAssert(contentURL);
                    
                    MXMediaManager *mediaManager = [[MXMediaManager alloc] initWithRestClient:mxSession.matrixRestClient];
                    XCTAssert(mediaManager);
                    
                    [mxSession close];

                    // Fake the case where our server was never not trusted
                    [[MXAllowedCertificates sharedInstance] reset];

                    // Then, try to download back the image
                    [mediaManager downloadMediaFromMatrixContentURI:contentURL
                                                                     withType:nil
                                                                     inFolder:nil
                                                                      success:^(NSString *outputFilePath) {
                                                                          XCTFail(@"The operation must fail because the self-signed certficate was not trusted (anymore)");
                                                                          [expectation fulfill];
                                                                      } failure:^(NSError *error) {
                                                                          [expectation fulfill];
                                                                      }];

                }];
            }];

            CGSize size = CGSizeMake(100, 100);
            UIImage *image = [self anImageWithSize:size];

            [room sendImage:UIImagePNGRepresentation(image) withImageSize:size mimeType:@"image/png" andThumbnail:nil threadId:nil localEcho:nil success:nil failure:^(NSError *error) {
                XCTFail(@"Cannot set up intial test conditions - error: %@", error);
                [expectation fulfill];
            }];

        } failure:^(NSError *error) {
            XCTFail(@"Cannot set up intial test conditions - error: %@", error);
            [expectation fulfill];
        }];
    }];
}
#endif

@end
