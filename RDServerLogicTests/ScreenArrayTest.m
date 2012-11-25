//
//  ScreenArrayTest.m
//  RDServer
//
//  Created by Rohan Shah on 8/7/12.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "ScreenArrayTest.h"
#import "ScreenArray.h"
#import "ScreenByteArray.h"

static NSString *NSStringFromRectArray(RectArray rectArray) {
    NSMutableString *result = [[NSMutableString alloc] init];
    
    [result appendFormat:@"{(%i):\n",rectArray.count];
    for(int i = 0; i < rectArray.count; i++)
        [result appendFormat:@"  %@\n",NSStringFromRect(NSRectFromCGRect(rectArray.array[i]))];
    [result appendFormat:@"}"];
    
    return [NSString stringWithString:[result autorelease]];
}

static BOOL rectArraysEqual(RectArray bit, RectArray byte) {
    if(bit.count != byte.count)
        goto failure;
    
    for(int i=0; i<bit.count; i++) {
        if(!CGRectEqualToRect(bit.array[i], byte.array[i]))
            goto failure;
    }
    
    return true;
    
failure:
    NSLog(@"bit: %@\n\nbyte: %@",
          NSStringFromRectArray(bit),
          NSStringFromRectArray(byte));
    return false;
}

@implementation ScreenArrayTest

-(void)testArrayInit {
    RDScreenRes res = ScreenResMake(10, 5);
    ScreenArray *bitArray = [[ScreenArray alloc] initWithSize:res];        
    RectArray bitResult = [bitArray dirtyRects];
    
    STAssertTrue(bitResult.count == 1, @"Result rect array count incorrect!");
    STAssertTrue(CGRectEqualToRect(bitResult.array[0],
                                   CGRectMake(0, 0, 10, 5)), 
                 @"Result rect incorrect!");
    
    NSLog(@"%@",NSStringFromRectArray(bitResult));
}

-(void)testSimpleClearout {
    RDScreenRes res = ScreenResMake(10, 5);
    ScreenArray *bitArray = [[ScreenArray alloc] initWithSize:res];
    [bitArray dirtyRects]; // clear out the array
    RectArray bitResult = [bitArray dirtyRects];
    
    STAssertTrue(bitResult.count == 0, @"Result rect array count incorrect!");
}

-(void)testOneRect {
    RDScreenRes res = ScreenResMake(10, 10);
    
    ScreenArray *bitArray = [[ScreenArray alloc] initWithSize:res];
    ScreenByteArray *byteArray = [[ScreenByteArray alloc] initWithSize:res];
    
    // clear out the arrays
    [bitArray dirtyRects];
    [byteArray dirtyRects];
    
    CGRect rects[1] = {
        CGRectMake(2, 2, 3, 4)
    };
    
    [bitArray fillRects:rects count:1];
    [byteArray fillRects:rects count:1];
    
    RectArray bitResult = [bitArray dirtyRects];
    RectArray byteResult = [byteArray dirtyRects];
    
    STAssertTrue(rectArraysEqual(bitResult, byteResult), @"Result rect arrays not equal!");
}


-(void)testManyRects {
    RDScreenRes res = ScreenResMake(10, 10);
    ScreenArray *bitArray = [[ScreenArray alloc] initWithSize:res];
    // clear out the array
    [bitArray dirtyRects];
    
    CGRect rects[3] = {
        CGRectMake(2, 3, 6, 3),
        CGRectMake(3, 2, 3, 6),
        CGRectMake(7, 7, 2, 2)
    };
    
    [bitArray fillRects:rects count:3];

    RectArray result = [bitArray dirtyRects];
    
    STAssertTrue(result.count == 4, @"Result rect array count incorrect!");
    STAssertTrue(CGRectEqualToRect(result.array[0], CGRectMake(3, 2, 3, 1)), @"Result rect 1 incorrect!");
    STAssertTrue(CGRectEqualToRect(result.array[1], CGRectMake(2, 3, 6, 3)), @"Result rect 2 incorrect!");
    STAssertTrue(CGRectEqualToRect(result.array[2], CGRectMake(3, 6, 3, 2)), @"Result rect 3 incorrect!");
    STAssertTrue(CGRectEqualToRect(result.array[3], CGRectMake(7, 7, 2, 2)), @"Result rect 4 incorrect!");
}

@end
