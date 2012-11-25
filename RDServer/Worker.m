//
//  Worker.m
//  RDServer
//
//  Created by Rohan Shah on 7/12/12.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "Worker.h"
#import "AppUtils.h"
#import "ProtocolConstants.h"
#import "ImageCompressor.h"
#import "ScreenArray.h"

#define DEFAULT_TAG 0

#define MESSAGE_CODE_TO_END_RANGE(l) (NSMakeRange(4, (l) - (4+[EOF_STR length])))
#define RECT_SIZE(x) ((x).size.width * (x).size.height)

@interface Worker ()
-(void)sendMessage:(NSString *)message;
-(void)authenticateWithHash:(NSString *)hash;

-(void)registerForScreenUpdates;
-(void)screenRectsUpdated:(CGRect *)rectArray count:(CGRectCount)count;
-(void)sendScreenUpdate;
@end

static void screenRefreshCallback(CGRectCount count, const CGRect *rectArray, void *userParam) {
    Worker *worker = (Worker *)userParam;
    [worker screenRectsUpdated:(CGRect *)rectArray count:count];
}

@implementation Worker
@synthesize manager;

#pragma mark - Init and dealloc

-(id)initWithID:(NSInteger)workerID {
    self = [super init];
    if(self) {
        [self retain];
        dispatchQueue = dispatch_queue_create([FORMAT(@"com.lateralcommunications.RDServer-Worker%i",workerID) cStringUsingEncoding:NSUTF8StringEncoding], 0);
    }
    return self;
}

-(void)dealloc {
    if(registeredForScreenUpdates) {
        CGUnregisterScreenRefreshCallback(screenRefreshCallback, self);
        registeredForScreenUpdates = NO;
    }
    
    [screenArray autorelease];
    self.socket.delegate = nil;
    self.socket = nil;
    [super dealloc];
}

#pragma mark - Connection events

-(void)beginConversation {
    [self sendMessage:AUTHENTICATION_REQUEST_MSG];
    [self.socket readDataToData:EOF_DATA withTimeout:TIMEOUT tag:DEFAULT_TAG];
}

-(NSTimeInterval)socket:(GCDAsyncSocket *)sock shouldTimeoutWriteWithTag:(long)tag elapsed:(NSTimeInterval)elapsed bytesDone:(NSUInteger)length {
    return (10.0 + lastMessage - [[NSDate date] timeIntervalSince1970]);
}

-(void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)err {
    if(err)
        [AppUtils handleNonFatalError:err context:@"socketDidDisconnect:"];
    
    authenticated = NO;
    
    [self.manager workerDidDisconnect];
    [self autorelease];
}

-(void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    lastMessage = [[NSDate date] timeIntervalSince1970];
    
    NSString *dataStr = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if(TELNET_MODE)
        dataStr = [dataStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *messageCode = [dataStr substringWithRange:NSMakeRange(0, 4)];
    
    
    if([messageCode isEqualToString:NOOP_MSG]) {
        [self sendMessage:NOOP_MSG];
        
    } else if([messageCode isEqualToString:AUTHENTICATE_MSG]) {
        [self authenticateWithHash:[dataStr substringWithRange:MESSAGE_CODE_TO_END_RANGE([dataStr length])]];
    
    } else if(authenticated) {
        if([messageCode isEqualToString:ALL_RECTS_RECEIVED_MSG])
            [self sendScreenUpdate];
    }
    
    [self.socket readDataToData:EOF_DATA withTimeout:TIMEOUT tag:DEFAULT_TAG];
}

#pragma mark - Authentication

-(void)authenticateWithHash:(NSString *)hash {
    
    authenticated = [hash isEqualToString:PASSWORD];
    [AppUtils log:FORMAT(@"Authenticated: %@", (authenticated ? @"YES" : @"NO"))];
    
    if(authenticated) {
        [self registerForScreenUpdates];
        [self sendScreenUpdate];
    }
}

#pragma mark - Sending screen updates

-(void)registerForScreenUpdates {
    if(registeredForScreenUpdates) {
        // no support (yet?) for calling registerForScreenUpdates twice in a row..
        NSError *error = [NSError errorWithDomain:@"registeredForScreenUpdates" code:1 userInfo:nil];
        [AppUtils handleError:error context:@"if(registeredForScreenUpdates) {...}"];
        return;
    }

    // send the current resolution
    RDScreenRes res = [ScreenController currentResolution];
    NSString *dataStr = FORMAT(@"%@%04d%04d%@",CURRENT_RESOLUTION_MSG,res.width,res.height,EOF_STR);
    [socket writeData:[dataStr dataUsingEncoding:NSUTF8StringEncoding] withTimeout:TIMEOUT tag:DEFAULT_TAG];
    
    // initialize the ScreenArray
    screenArray = [[ScreenArray alloc] initWithSize:res];
    
    // register for screen updates
    CGRegisterScreenRefreshCallback(screenRefreshCallback, self);
    registeredForScreenUpdates = YES;
}

-(void)screenRectsUpdated:(CGRect *)rectArray count:(CGRectCount)count {
    [screenArray fillRects:(CGRect *)rectArray count:(CGRectCount)count];

    if(!sendingRects) {
        // We're probably on the main thread, which we don't want to block. We also don't want to just fire this off on any thead because two of them running simultaneously would be bad, so let's put it in the dispatch queue. 
        dispatch_async(dispatchQueue, ^{
            [self sendScreenUpdate];
        });
    }
}

-(void)sendScreenUpdate {
    __block RectArray rects = [screenArray dirtyRects];
    if(rects.count == 0) {
        sendingRects = NO;
        free(rects.array);
        return;
    } else {
        sendingRects = YES;
    }
    
    // Count and send the number of "real" (non-blank) rects to send.
    int realRectsCount = 0;
    for(int i=0;i<rects.count;i++)
        if(!CGRectEqualToRect(rects.array[i],CGRectZero))
            realRectsCount++;
    
    NSData *data = [FORMAT(@"%@%i%@", SCREEN_MSG,realRectsCount,EOF_STR) dataUsingEncoding:NSUTF8StringEncoding];
    [self.socket writeData:data withTimeout:TIMEOUT tag:0];
    
    rects.retainCount = rects.count;
    dispatch_apply(rects.count, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i) {
        CGRect rect = rects.array[i];

        if(CGRectEqualToRect(rect, CGRectZero)) {
            rects.retainCount--;
            if(rects.retainCount == 0) {
                free(rects.array);
            }
            return;
        }
        
        CGImageRef screenshot = CGDisplayCreateImageForRect(kCGDirectMainDisplay, rect); 
        NSData *screenshotData;
        if(!screenshot) {
            screenshotData = [NSData data];
        } else {
            screenshotData = compressImage(screenshot);
            CGImageRelease(screenshot);
        }
        
        NSMutableData *data = [NSMutableData dataWithCapacity:[screenshotData length]+[SCREEN_RECT_MSG length]+8]; // 8 = len(%04d) + len(%04d)
        [data appendData:[FORMAT(@"%@%04d%04d", SCREEN_RECT_MSG, (int)rect.origin.x, (int)(screenArray.height-rect.origin.y-rect.size.height)) dataUsingEncoding:NSUTF8StringEncoding]];
        [data appendData:screenshotData];
        [data appendData:EOF_DATA];
        
        [self.socket writeData:data withTimeout:TIMEOUT tag:DEFAULT_TAG];
    
        rects.retainCount--;
        if(rects.retainCount == 0) {
            free(rects.array);
        }
    });
}

#pragma mark - Miscellaneous

// send a control message over the line
-(void)sendMessage:(NSString *)message {
    NSString *messageStr = FORMAT(@"%@%@", message,EOF_STR);
    NSData *messageData = [messageStr dataUsingEncoding:NSUTF8StringEncoding];
    
    [self.socket writeData:messageData withTimeout:TIMEOUT tag:DEFAULT_TAG];
}


// Custom property methods for socket because we need to do some stuff on assignment.

-(GCDAsyncSocket *)socket {
    GCDAsyncSocket *result;
    @synchronized(self) {
        result = [socket retain];
    }
    return [result autorelease];
}

-(void)setSocket:(GCDAsyncSocket *)newSocket {
    @synchronized(self) {
        if (socket != newSocket) {
            [socket release];
            socket = [newSocket retain];
            
            socket.delegate = self;
            socket.delegateQueue = dispatchQueue;
        }
    }
}


@end
