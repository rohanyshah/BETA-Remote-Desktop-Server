//
//  Worker.h
//  RDServer
//
//  Created by Rohan Shah on 7/12/12.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GCDAsyncSocket.h"
#import "ScreenController.h"

@protocol WorkerManager
-(void)workerDidDisconnect;
@end

@class ScreenArray;
@interface Worker : NSObject <GCDAsyncSocketDelegate> {
    dispatch_queue_t dispatchQueue;
    GCDAsyncSocket *socket;
    id <WorkerManager> manager;
    BOOL authenticated;
    NSTimeInterval lastMessage;
    
    BOOL registeredForScreenUpdates;
    ScreenArray *screenArray;
    BOOL sendingRects;
}
@property(retain) GCDAsyncSocket *socket;
@property(assign) id <WorkerManager> manager;

-(id)initWithID:(NSInteger)workerID;
-(void)beginConversation;

@end
