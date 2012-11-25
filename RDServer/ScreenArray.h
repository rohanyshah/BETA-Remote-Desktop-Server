//
//  ScreenArray.h
//  RDServer
//
//  Created by Rohan Shah on 7/24/12.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//
#import "ScreenController.h"
#import "RectArray.h"

@interface ScreenArray : NSObject {
    RDScreenRes resolution;
    int bytesPerRow;
    unsigned char *array;
    int arrayLength;
}

-(id)initWithSize:(RDScreenRes)size;
-(void)fillRects:(CGRect *)rectArray count:(CGRectCount)count;
-(RectArray)dirtyRects;

-(NSUInteger)height;

@end
