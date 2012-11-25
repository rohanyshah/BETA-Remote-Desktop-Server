//
//  RDServerAppDelegate.m
//  RDServer
//
//  Created by Rohan Shah on 7/12/12.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "RDServerAppDelegate.h"
#import "AppUtils.h"
#import "ScreenController.h"
#import "Worker.h"
#import "ProtocolConstants.h"

@implementation RDServerAppDelegate

@synthesize window;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    socketQueue = dispatch_queue_create("com.lateralcommunications.rdserver-socketqueue", NULL);
    listenSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:socketQueue];
    
    NSError *err = nil;
    if(![listenSocket acceptOnPort:PORT error:&err])
        [AppUtils handleError:err context:@"applicationDidFinishLaunching:"];
}

-(void)socket:(GCDAsyncSocket *)sock didAcceptNewSocket:(GCDAsyncSocket *)newSocket {
    workersCreated++;
    [ScreenController changeResolution];
    
    NSString *host = [newSocket connectedHost];
	UInt16 port = [newSocket connectedPort];
    [AppUtils log:FORMAT(@"Accepted client %@:%i", host, port)];
    
    Worker *worker = [[Worker alloc] initWithID:workersCreated];
    worker.socket = newSocket;
    worker.manager = self;
    
    [worker beginConversation];
    [worker release];
}

-(void)workerDidDisconnect {
    workersDestroyed++;
    if(workersCreated == workersDestroyed)
        [ScreenController restoreOriginalResolution];
}

-(void)applicationWillTerminate:(NSNotification *)notification {
    [ScreenController restoreOriginalResolution];
}

-(void)dealloc {
    [listenSocket release];
    [super dealloc];
}

@end
