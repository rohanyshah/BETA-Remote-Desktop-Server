//
//  AppUtils.m
//  RDServer
//
//  Created by Rohan Shah on 7/3/12.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "AppUtils.h"

@implementation AppUtils

+(void)log:(NSString *)message {
    if(![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"%@",message);
        });
    } else {
        NSLog(@"%@",message);
    }
}

+(void)handleError:(NSError *)error context:(NSString *)context {
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSLog(@"Error! Context: %@ \n Error: %@\n User info: %@",context,error,[error userInfo]);
        exit(1);
    });
}

+(void)handleNonFatalError:(NSError *)error context:(NSString *)context {
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSLog(@"Error! Context: %@ \n Error: %@\n User info: %@",context,error,[error userInfo]);
    });
}

@end
