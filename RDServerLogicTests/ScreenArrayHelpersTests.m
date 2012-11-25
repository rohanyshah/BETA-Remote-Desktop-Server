//
//  RDServerLogicTests.m
//  RDServerLogicTests
//
//  Created by Rohan Shah on 8/7/12.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "ScreenArrayHelpersTests.h"
#include "../RDServer/ScreenArrayHelpers.m"

@implementation ScreenArrayHelpersTests

-(void)testOneAt {
    STAssertEquals(one_at(0), (unsigned char)0b10000000, @"one_at(0) failed!");
    STAssertEquals(one_at(1), (unsigned char)0b01000000, @"one_at(1) failed!");
    STAssertEquals(one_at(2), (unsigned char)0b00100000, @"one_at(2) failed!");
    STAssertEquals(one_at(3), (unsigned char)0b00010000, @"one_at(3) failed!");
    STAssertEquals(one_at(4), (unsigned char)0b00001000, @"one_at(4) failed!");
    STAssertEquals(one_at(5), (unsigned char)0b00000100, @"one_at(5) failed!");
    STAssertEquals(one_at(6), (unsigned char)0b00000010, @"one_at(6) failed!");
    STAssertEquals(one_at(7), (unsigned char)0b00000001, @"one_at(7) failed!");
}

-(void)testZeroAt {
    STAssertEquals(zero_at(0), (unsigned char)0b01111111, @"zero_at(0) failed!");
    STAssertEquals(zero_at(1), (unsigned char)0b10111111, @"zero_at(1) failed!");
    STAssertEquals(zero_at(2), (unsigned char)0b11011111, @"zero_at(2) failed!");
    STAssertEquals(zero_at(3), (unsigned char)0b11101111, @"zero_at(3) failed!");
    STAssertEquals(zero_at(4), (unsigned char)0b11110111, @"zero_at(4) failed!");
    STAssertEquals(zero_at(5), (unsigned char)0b11111011, @"zero_at(5) failed!");
    STAssertEquals(zero_at(6), (unsigned char)0b11111101, @"zero_at(6) failed!");
    STAssertEquals(zero_at(7), (unsigned char)0b11111110, @"zero_at(7) failed!");
}

-(void)testBitAt {
    unsigned char byte = 0b10101001;
    STAssertTrue(bit_at(byte, 0), @"bit_at(0) failed!");
    STAssertFalse(bit_at(byte, 1), @"bit_at(1) failed!");
    STAssertTrue(bit_at(byte, 2), @"bit_at(2) failed!");
    STAssertFalse(bit_at(byte, 3), @"bit_at(3) failed!");
    STAssertTrue(bit_at(byte, 4), @"bit_at(4) failed!");
    STAssertFalse(bit_at(byte, 5), @"bit_at(5) failed!");
    STAssertFalse(bit_at(byte, 6), @"bit_at(6) failed!");
    STAssertTrue(bit_at(byte, 7), @"bit_at(7) failed!");
}

-(void)testFillRow {
    unsigned char array[4];
    unsigned char reference[4] = {
        0b00000000, 0b00111111, 0b11111000, 0b00000000
    };
    
    fill_row(array, 10, 11, YES);
    
    for(int i = 0; i < 4; i++)
        STAssertEquals(array[i], reference[i], @"fill_row failed! bit %i: %x != %x", i, array[i], reference[i]);
}


-(void)testFillRow2 {
    unsigned char array[20];
    unsigned char reference[20] = {
        0b00000000, 0b00000000, 
        0b00000000, 0b00000000,
        0b00111000, 0b00000000, 
        0b00000000, 0b00000000, 
        0b00000000, 0b00000000, 
        0b00000000, 0b00000000, 
        0b00000000, 0b00000000, 
        0b00000000, 0b00000000, 
        0b00000000, 0b00000000, 
        0b00000000, 0b00000000 
    };
    
    fill_row(array, 34, 3, YES);
    
    for(int i = 0; i < 20; i++)
        STAssertEquals(array[i], reference[i], @"fill_rect failed! bit %i: %x != %x", i, array[i], reference[i]);
}

-(void)testFillRect {
    unsigned char array[12];
    unsigned char reference[12] = {
        0b00000000, 0b00000000, 0b00000000, 0b00000000,
        0b00000000, 0b00111111, 0b11111000, 0b00000000,
        0b00000000, 0b00111111, 0b11111000, 0b00000000
    };
    
    fill_rect(array, 4, CGRectMake(10, 1, 11, 2), YES);
    
    for(int i = 0; i < 12; i++)
        STAssertEquals(array[i], reference[i], @"fill_rect failed! bit %i: %x != %x", i, array[i], reference[i]);
}

-(void)testFindNextBit {
    unsigned char array[4] = { 
        0b00011111, 0b11111111,
        0b00011111, 0b11000000
    };
    
    int result = find_next_bit(array, 
                               4, 
                               0, 
                               YES, 
                               YES);
    STAssertEquals(result, 3, @"find_next_bit failed! (1)");
    
    // if it can't find what it's looking for, it should return the index of the next bit after the offset.
    result = find_next_bit(array, 
                           2, 
                           3, 
                           NO, 
                           NO);    
    STAssertEquals(result, 16, @"find_next_bit failed! (2)");

    // same as the last test, except it should be able to find what it's looking for (and return it).
    result = find_next_bit(array, 
                           4, 
                           3, 
                           NO, 
                           NO);    
    STAssertEquals(result, 16, @"find_next_bit failed! (3)");
    
    // now, try to find the end of the run in the second row.
    result = find_next_bit(array, 
                           4, 
                           19, 
                           NO, 
                           NO);    
    STAssertEquals(result, 26, @"find_next_bit failed! (4)");
    
    // try to overrun the array and return -1
    result = find_next_bit(array, 
                           4, 
                           26, 
                           YES, 
                           YES);    
    STAssertEquals(result, -1, @"find_next_bit failed! (5)");
}

@end
