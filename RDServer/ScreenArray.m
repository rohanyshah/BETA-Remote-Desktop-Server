//
//  ScreenArray.m
//  RDServer
//
//  Created by Rohan Shah on 7/24/12.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "ScreenArray.h"

#define RECT_SIZE(x) ((x).size.width * (x).size.height)

#include "ScreenArrayHelpers.m"

#pragma mark - Debug functions 

static void binary(unsigned char byte, char **buffer) {
    for(int i=0; i<8; i++) {
        (*buffer)[i] = (bit_at(byte, i) ? '1' : '0');
    }
    (*buffer)[8] = '\0';
}

static void print_array(unsigned char *array, int array_length, int bytes_per_row) {
    printf("\n");printf("\n");
    
    int height = array_length / bytes_per_row;
    for(int i = 0; i < height; i++) {
        for(int j=0; j<bytes_per_row; j++) {
            char *buffer = malloc(sizeof(char) * 9);
            binary(array[i*bytes_per_row + j], &buffer);
            printf("0b%s ", buffer);
            free(buffer);
        }
        printf("\n");
    }
    
    printf("\n");printf("\n");
}

@implementation ScreenArray

#pragma mark - Init and dealloc

- (id)initWithSize:(RDScreenRes)size {
    self = [super init];
    if (self) {
        @synchronized(self) {
            resolution = size;
            // divide by eight and round up
            bytesPerRow = (int)(resolution.width / 8) + (resolution.width % 8 == 0 ? 0 : 1);
            arrayLength = (int)(bytesPerRow * resolution.height);
            
            array = malloc(arrayLength);
            memset(array, 0, arrayLength); // the bits at the end of each row must be zeroes
                        
            // we don't just write ALL_ONES to the array because we want the padding bits at the end of each row to be 0.
            fill_rect(array, bytesPerRow, CGRectMake(0, 0, resolution.width, resolution.height), YES);
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
            fill_rect(array, bytesPerRow, rectArray[i], YES);
        }
    }
}

-(RectArray)dirtyRects {
    RectArray result;
    result.count = 0;
    result.capacity = 5;
    result.array = malloc(sizeof(CGRect)*result.capacity);
    
    @synchronized(self) {
        
        int bits_per_row = bytesPerRow * 8;
        
        int bit_offset = 0;
        int rect_beginning = 0;
        
        while ((rect_beginning = find_next_bit(array, arrayLength, bit_offset, YES, YES)) != -1) {
            bit_offset = rect_beginning;
            
            int rect_origin_x = (rect_beginning % bits_per_row);
            // the next line is basically equivalent to rect_row_end = ceil(rect_beginning / bits_per_row)
            int rect_row_end = ((rect_beginning + bits_per_row - 1) / bits_per_row) * bytesPerRow;
            if(rect_origin_x % bits_per_row == 0)
                rect_row_end += bytesPerRow;
            
            int rect_end_bit = find_next_bit(array, 
                                             rect_row_end, // location of the end of the row
                                             rect_beginning, 
                                             NO,
                                             NO);
            int rect_width = rect_end_bit - rect_beginning;

            int rect_height = 1;
            int row_end;
            while (
                   (row_end = rect_row_end + ((rect_height) * bytesPerRow)) <= arrayLength && 
                   find_next_bit(array, 
                                 row_end, 
                                 rect_beginning + ((rect_height) * bits_per_row),
                                 NO,
                                 NO
                                 ) - ((rect_height)*bits_per_row) == rect_end_bit
                   ) 
            {
                rect_height++;
            }
            
            CGRect rect = CGRectMake(rect_origin_x, rect_beginning / bits_per_row, rect_width, rect_height);
            fill_rect(array, bytesPerRow, rect, NO);
            
            result.count = result.count + 1;
            if(result.count > result.capacity) {
                result.capacity += 5;
                result.array = realloc(result.array, sizeof(CGRect)*result.capacity);
            }
            result.array[result.count - 1] = rect;
            
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
