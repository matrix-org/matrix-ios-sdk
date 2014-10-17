Matrix iOS SDK
==============

This open-source library allows you to build iOS apps compatible with Matrix (http://www.matrix.org), an open standard for interoperable Instant Messaging and VoIP.

This SDK implements an interface to communicate with the Matrix Home Server API which is defined at http://matrix.org/docs/api/client-server/.


Installation
============

The SDK uses CocoaPods (http://cocoapods.org/) as library dependency manager.
The best way to add the Matrix SDK to your application project is to add the MatrixSDK dependency to your Podfile::
    
      pod 'MatrixSDK', :path => '../../MatrixSDK.podspec' // TODO: Register our podspec at cocoaPods


Overview
========

As a quick overview, there are four classes to know to use the SDK.

Matrix API level
----------------
The Matrix API level classes expose the Matrix Client-Server API as specified by the Matrix standard to make requests to a Home Server. 
This is realised by two classes:

:``MXHomeServer``:
    It exposes the Matrix Client-Server API part that does not require the user to be authenticated. With this class, you can get a list of public rooms available on an home server. You can also register or login a user so that you can open a MXSession to the home server.

:``MXSession``:
    It exposes the Matrix Client-Server API part that requires the user to be authenticated. This class requires a user ID and his access token to be instantiated.


Business logic and data model
-----------------------------
At an upper level, you will find helper to handle data coming from the Home Server.
These classes does logic to maintain consistent chat rooms data.

:``MXData``:
    This is the main point to handle all data: it uses a MXSession instance to loads and maintains data from the home server. The collected data is then dispatched into MXRoomData objects.

:``MXRoomData``:
	 This is the data associated to one room. Among other things, it contains messages downloaded so far and the list of members. The app can register handlers to be notified when there was changes in the room (new events).


Usage
=====

The sample app (https://github.com/matrix-org/matrix-ios-sdk/tree/master/samples/syMessaging) demonstrates how to build a chat app on top of Matrix. You can refer to it, play with it, hack it to understand the full integration of the Matrix SDK.
This section comes back to the basics with sample codes for basic use cases.

One file to import::

      #import <MatrixSDK/MatrixSDK.h>
  
Use case #1: Get public rooms of an home server
-----------------------------------------------
This API does not require the user to be authenticated. So, MXHomeServer does the job::

    MXHomeServer *homeServer = [[MXHomeServer alloc] initWithHomeServer:@"http://matrix.org"];
    [homeServer publicRooms:^(NSArray *rooms) {
        
        // rooms is an array of MXPublicRoom objects containing information like room id
        NSLog(@"The public rooms are: %@", rooms);
        
    } failure:^(MXError *error) {
    }];


Use case #2: Get the rooms user has interaction with
----------------------------------------------------
Here the user needs to be authenticated. We will use MXSession combined with MXData that will help us to get organised data.
The set up of these two objects is usually done once in the app for the user login life::

    // Create a matrix session
    MXSession *mxSession = [[MXSession alloc] initWithHomeServer:@"http://matrix.org"
                                                              userId:@"@your_user_id:matrix.org"
                                                         accessToken:@"your_access_tokem"];
    
    // Set up matrix data
    MXData *mxData = [[MXData alloc] initWithMatrixSession:mxSession];
    
    // Launch mxData: it will first make an initial sync with the home server
    // Then it will listen to new coming events and update its data
    [mxData start:^{
        
        // mxData is ready to be used
        
    } failure:^(NSError *error) {
    }];

And now, we can get all rooms in::

    mxData.roomDatas
	
	
Use case #3: Get messages of a room
-----------------------------------
We reuse the mxData instance created before::

    // Retrieve the room data
    MXRoomData *roomData = [mxData getRoomData:@"!room_id:matrix.org"];
    
    // Messages are here (in the form of MXEvents array):
    roomData.messages;
	
roomData.messages are the most recents messages in the room downloaded so far. If you want more messages from the past, use paginateBackMessages::

    [roomData paginateBackMessages:10 success:^(NSArray *messages) {
        
        // messages contains the newly retrieved past events
        // Note that roomData.messages has been updated with these events
        
    } failure:^(NSError *error) {
    }];
	
What about coming new events? You need to register a listener to get them::

    [roomData registerEventListenerForTypes:nil block:^(MXRoomData *roomData, MXEvent *event, BOOL isLive) {
        
        // If isLive is YES, event is new event coming to the room
        // Same note as before: roomData.messages has been updated with this new event
        
    }];


Use case #4: Post a text message to a room
------------------------------------------
This action does not require any business logic from MXData. MXSession is directly used::

    [mxSession postTextMessage:@"the_room_id" text:@"Hello world!" success:^(NSString *event_id) {
        
        // event_id is for reference
        // If you have registered events listener like in the previous use case, you will get
        // a notification for this event coming down from the home server events stream and
        // now handled by MXData.
        
    } failure:^(NSError *error) {
    }];
	
	
Tests
=====
The SDK Xcode project embeds both unit and integration tests.

The integration tests use one of the home servers of the "Demo Federation of Homeservers" (https://github.com/matrix-org/synapse#running-a-demo-federation-of-homeservers). You have to start them from your local Synapse folder::

      $ demo/start.sh

Then, you can run the tests from the Xcode Test navigator tab or select the MatrixSDKTests scheme and click on the "Test" action.

Out of the box, tests point to a home server located at http://localhost:8080. This is very convenient when you launch tests on the iOS simulator with a home server running on the same Mac machine. 

If you want to run tests on a real iOS device, you will need to replace localhost by the name or the IP of the machine hosting the homeserver. This can be achieved by changing the value of kMXTestsHomeServerURL in MatrixSDKTestsData.m::

      NSString *const kMXTestsHomeServerURL = @"http://localhost:8080";


Known issues
============

Registration
------------
The SDK currently manages only login-password type registration.
This type of registration is not accepted by the home server hosted at matrix.org. It has been disabled for security and spamming reasons.
So, for now, you will be not be able to register a new account with the SDK on such home server. But you can login an existing user.

If you run your own home server, the default launch parameters enables the login-password type registration and you will be able to register a new user to it.


