//
//  ScreenArray.m
//  RDServer
//
//  Created by Rohan Shah on 7/24/12.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "ScreenByteArray.h"

#define PIXEL_LOC(x,y) ((x)+(resolution.width*(y)))
#define RECT_SIZE(x) ((x).size.width * (x).size.height)

static inline void fill_rect(BOOL *array,
                            const RDScreenRes resolution, 
                            const CGRect rect, 
                            const BOOL value) {
    int ylimit = (int)(rect.origin.y + rect.size.height);
    for(int y = (int)rect.origin.y; y < ylimit; y++) {
        int x = (int)rect.origin.x;
        memset(array+PIXEL_LOC(x, y), (int)value, (size_t)rect.size.width);
    }
}

@interface ScreenByteArray ()
@end

@implementation ScreenByteArray

#pragma mark - Init and dealloc

- (id)initWithSize:(RDScreenRes)size {
    self = [super init];
    if (self) {
        @synchronized(self) {
            resolution = size;
            size_t arrLength = sizeof(BOOL) * resolution.width * resolution.height;
            array = malloc(arrLength);
            memset(array,  (int)YES, arrLength);
        }
    }
    return self;
}

-(void)dealloc {
    @synchronized(self) {
        free(array);
    }
    [super dealloc];
}

#pragma mark - Operations

-(void)fillRects:(CGRect *)rectArray count:(CGRectCount)count {
    @synchronized(self) {
        for (int i=0; i<count; i++) {
            fill_rect(array, resolution, rectArray[i], YES);
        }
    }
}

-(RectArray)dirtyRects {
    RectArray result;
    result.count = 0;
    result.capacity = 5;
    result.array = malloc(sizeof(CGRect)*result.capacity);
    
    @synchronized(self) {
        
        for(int y = 0; y < resolution.height; y++) {
            for(int x = 0; x < resolution.width; x++) {
                
                if(array[PIXEL_LOC(x, y)]) {
                    
                    int rectWidth = 0;
                    while(
                          (x+rectWidth < resolution.width) && 
                          (array[PIXEL_LOC(x+rectWidth, y)])
                          )
                        rectWidth++;
                    
                    int rectHeight = 0;
                    BOOL stop = NO;
                    while(!stop) {
                        for(int x2 = x; x2 < x + rectWidth; x2++) {
                            
                            if(
                               (y+rectHeight >= resolution.height) ||
                               (!array[PIXEL_LOC(x2, y+rectHeight)])
                               ) {
                                stop = YES;
                                break;
                            }
                        }
                        if(!stop)
                            rectHeight++;
                    }
                    
                    CGRect rect = CGRectMake((CGFloat)x, (CGFloat)y, (CGFloat)rectWidth, (CGFloat)rectHeight);
                    fill_rect(array, resolution, rect, NO);
                    
                    result.count = result.count + 1;
                    if(result.count > result.capacity) {
                        result.capacity += 5;
                        result.array = realloc(result.array, sizeof(CGRect)*result.capacity);
                    }
                    result.array[result.count - 1] = rect;
                }
            }
        }
    }
    
//    if(result.count >= 2) {
//        for(int i=0;i<result.count-1;i++) {
//            CGRect unionRect = CGRectUnion(result.array[0], result.array[1]);
//            
//            CGFloat rectSizeRatio = RECT_SIZE(unionRect)/(RECT_SIZE(result.array[0]) + RECT_SIZE(result.array[1]));
//            if(rectSizeRatio <= 1.5) {
//                result.array[0] = CGRectZero;
//                result.array[1] = unionRect;
//            }
//        }
//    }
    
    return result;
}

-(NSUInteger)height {
    return resolution.height;
}

@end
