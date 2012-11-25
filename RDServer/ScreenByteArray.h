//
//  ScreenArray.h
//  RDServer
//
//  Created by Rohan Shah on 7/24/12.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//
#import "ScreenController.h"
#import "RectArray.h"

@interface ScreenByteArray : NSObject {
    RDScreenRes resolution; 
    BOOL *array;
}

-(id)initWithSize:(RDScreenRes)size;
-(void)fillRects:(CGRect *)rectArray count:(CGRectCount)count;
-(RectArray)dirtyRects;

-(NSUInteger)height;

@end
