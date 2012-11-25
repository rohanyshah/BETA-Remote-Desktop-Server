//
//  RDServerAppDelegate.h
//  RDServer
//
//  Created by Rohan Shah on 7/12/12.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "GCDAsyncSocket.h"
#import "Worker.h"

@class ServerSocketDelegate;
@interface RDServerAppDelegate : NSObject <NSApplicationDelegate, GCDAsyncSocketDelegate, WorkerManager> {
    NSWindow *window;
    
    dispatch_queue_t socketQueue;
    GCDAsyncSocket *listenSocket;
    
    int workersCreated;
    int workersDestroyed;
}

@property (assign) IBOutlet NSWindow *window;

@end
