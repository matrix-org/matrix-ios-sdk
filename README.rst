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

As a quick overview, there are the classes to know to use the SDK.

Matrix API level
----------------
:``MXRestClient``:
    It exposes the Matrix Client-Server API as specified by the Matrix standard to make requests to a Home Server. 


Business logic and data model
-----------------------------
At an upper level, you will find helper to handle data coming from the Home Server.
These classes does logic to maintain consistent chat rooms data.

:``MXSession``:
    This is the main point to handle all data: it uses a MXRestClient instance to loads and maintains data from the home server. The collected data is then dispatched into MXRoom, MXRoomState, MXRoomMember and MXUser objects.

:``MXRoom``:
	 This is the data associated to one room. Among other things, it contains -messages downloaded so far- and the list of members. The app can register handlers to be notified when there was changes in the room (new events).
	 TODO

:``MXRoomState``:
	 TODO
	 
:``MXRoomMember``:
	 TODO
	 
:``MXUser``:
	 TODO

Usage
=====

The sample app (https://github.com/matrix-org/matrix-ios-sdk/tree/master/samples/matrixConsole) demonstrates how to build a chat app on top of Matrix. You can refer to it, play with it, hack it to understand the full integration of the Matrix SDK.
This section comes back to the basics with sample codes for basic use cases.

One file to import::

      #import <MatrixSDK/MatrixSDK.h>
  
Use case #1: Get public rooms of an home server
-----------------------------------------------
This API does not require the user to be authenticated. So, MXRestClient instantiated with initWithHomeServer does the job::

    MXRestClient *mxRestClient = [[MXRestClient alloc] initWithHomeServer:@"http://matrix.org"];
    [mxRestClient publicRooms:^(NSArray *rooms) {
        
        // rooms is an array of MXPublicRoom objects containing information like room id
        NSLog(@"The public rooms are: %@", rooms);
        
    } failure:^(MXError *error) {
    }];


Use case #2: Get the rooms user has interaction with
----------------------------------------------------
Here the user needs to be authenticated. We will use [MXRestClient initWithCredentials] combined with MXSession that will help us to get organised data.
The set up of these two objects is usually done once in the app for the user login life::


    MXCredentials *credentials = [[MXCredentials alloc] initWithHomeServer:@"http://matrix.org"
                                                                    userId:@"@your_user_id:matrix.org"
                                                               accessToken:@"your_access_tokem"];

    // Create a matrix session
    MXRestClient *mxRestClient = [[MXRestClient alloc] initWithCredentials:credentials];
    
    // Create a matrix session
    MXSession *mxSession = [[MXSession alloc] initWithMatrixRestClient:mxRestClient];
    
    // Launch mxSession: it will first make an initial sync with the home server
    // Then it will listen to new coming events and update its data
    [mxSession start:^{
        
        // mxSession is ready to be used
		// Now we can get all rooms with:
		mxSession.rooms;
        
    } failure:^(NSError *error) {
    }];

	
	
Use case #3: Get messages of a room
-----------------------------------
We reuse the mxSession instance created before::

    // Retrieve the room from its room id
    MXRoom *room = [mxSession room:@"!room_id:matrix.org"];
	
	// Add a listener on events related to this room
	[room listenToEvents:^(MXEvent *event, MXEventDirection direction, MXRoomState *roomState) {
	
		if (direction == MXEventDirectionForwards) {
			// Live/New events come here
		}
		else if (direction == MXEventDirectionBackwards) {
			// Events that occured in the past will come here when requesting pagination.
			// roomState contains the state of the room just before this event occured.
		}
	}];

	
Let's load a bit of room history using paginateBackMessages::

	// Reset the pagination start point to now
	[room resetBackState];

    [room paginateBackMessages:10 complete:^{
        
        // At this point, the SDK has finished to enumerate the events to the attached listeners
        
    } failure:^(NSError *error) {
    }];
	


Use case #4: Post a text message to a room
------------------------------------------
This action does not require any business logic from MXSession. MXRestClient is directly used::

    [MXRestClient postTextMessage:@"the_room_id" text:@"Hello world!" success:^(NSString *event_id) {
        
        // event_id is for reference
        // If you have registered events listener like in the previous use case, you will get
        // a notification for this event coming down from the home server events stream and
        // now handled by MXSession.
        
    } failure:^(NSError *error) {
    }];
	
	
Tests
=====
The tests in the SDK Xcode project are both unit and integration tests.

Out of the box, the tests use one of the home servers (located at http://localhost:8080 )of the "Demo Federation of Homeservers" (https://github.com/matrix-org/synapse#running-a-demo-federation-of-homeservers). You have to start them from your local Synapse folder::

      $ demo/start.sh --no-rate-limit

Then, you can run the tests from the Xcode Test navigator tab or select the MatrixSDKTests scheme and click on the "Test" action.


Known issues
============

Registration
------------
The SDK currently manages only login-password type registration.
This type of registration is not accepted by the home server hosted at matrix.org. It has been disabled for security and spamming reasons.
So, for now, you will be not be able to register a new account with the SDK on such home server. But you can login an existing user.

If you run your own home server, the default launch parameters enables the login-password type registration and you will be able to register a new user to it.


