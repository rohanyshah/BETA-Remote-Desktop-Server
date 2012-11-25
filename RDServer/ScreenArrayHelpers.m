//
//  ScreenArrayHelpers.m
//  RDServer
//
//  Created by Rohan Shah on 8/7/12.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

// this code used to be in ScreenArray, but was refactored here so that it could be unit tested.

#define ALL_ONES 0b11111111
#define ALL_ZEROES 0b00000000

static inline unsigned char leading_ones(const unsigned char ones) {
    switch (ones) {
        case 0:
            return 0b00000000;
        case 1:
            return 0b10000000;
        case 2:
            return 0b11000000;
        case 3:
            return 0b11100000;
        case 4:
            return 0b11110000;
        case 5:
            return 0b11111000;
        case 6:
            return 0b11111100;
        case 7:
            return 0b11111110;
        default:
            return 0b11111111;
    }
}

static inline unsigned char leading_zeroes(const unsigned char zeroes) {
    switch (zeroes) {
        case 0:
            return 0b11111111;
        case 1:
            return 0b01111111;
        case 2:
            return 0b00111111;
        case 3:
            return 0b00011111;
        case 4:
            return 0b00001111;
        case 5:
            return 0b00000111;
        case 6:
            return 0b00000011;
        case 7:
            return 0b00000001;
        default:
            return 0b00000000;
    }
}

static inline unsigned char one_at(const int location) {
    return 0b10000000 >> location;
}

static inline unsigned char zero_at(const int location) {
    return leading_ones(location) | leading_zeroes(location+1);
}

static inline unsigned char bit_at(const unsigned char byte,
                                   const int location) {
    return (byte & one_at(location));
}

static inline void fill_row(unsigned char *array,
                            const int start_bit,
                            int length,
                            const BOOL value) {
    int byte = start_bit / 8;
    
    if(length < 8) {
        // special case: if length is less than 8, the code below
        // won't work (and it would be pointless to try to make it work), 
        // so we'll take a slower, simpler approach.
        
        int bit = start_bit % 8;
        while (length > 0 && bit < 8) {
            if(value)
                array[byte] = array[byte] | one_at(bit);
            else
                array[byte] = array[byte] & zero_at(bit);
            
            bit++;
            length--;
        }
        
        // it's possible that we've run out of room on that byte without
        // finishing the row fill, so we handle one more byte here. note
        // that this approach (length < 8) will never need to handle more
        // than two bytes.
        if(length > 0) {
            byte++;
            bit = 0;
            while (length > 0) {
                if(value)
                    array[byte] = array[byte] | one_at(bit);
                else
                    array[byte] = array[byte] & zero_at(bit);
                bit++;
                length--;
            }
        }
        
        return;
    }
    
    // write the first byte
    if(value)
        array[byte] = array[byte] | leading_zeroes(start_bit % 8);
    else
        array[byte] = array[byte] & leading_ones(start_bit % 8);
    
    length -= (8 - (start_bit%8));
    byte++;
    
    // write the bytes in the middle
    while (length >= 8) {
        array[byte] = (value ? ALL_ONES : ALL_ZEROES);
        length -= 8;
        byte++;
    }
    
    // write the end byte
    if(value)
        array[byte] = array[byte] | leading_ones(length);
    else
        array[byte] = array[byte] & leading_zeroes(length);
}

static void fill_rect(unsigned char *array,
                      const int bytesPerRow,
                      const CGRect rect, 
                      const BOOL value) {
    
    int width = (int)rect.size.width;
    int ylimit = (int)(rect.origin.y + rect.size.height);
    
    for(int y = (int)rect.origin.y; y < ylimit; y++) {
        fill_row(array, (bytesPerRow*y*8)+rect.origin.x, width, value);
    }
}

static int find_next_bit(const unsigned char *array,
                         const int array_length,
                         const int bit_offset,
                         BOOL look_for_set_bit,
                         BOOL return_negative_on_not_found) {
    
   // NSLog(@"FNB(len: %i, offset: %i, %i, %i)", array_length, bit_offset, !!look_for_set_bit, !!return_negative_on_not_found);
    
    int byte_offset = bit_offset/8;
    unsigned char byte;
    if(look_for_set_bit)
        byte = array[byte_offset] & leading_zeroes(bit_offset % 8);
    else
        byte = array[byte_offset] | leading_ones(bit_offset % 8);
    
    if(look_for_set_bit) {
        while (!byte && (byte_offset < array_length)) {
            byte_offset++;
            byte = array[byte_offset];
        }   
    } else {
        while ((byte == ALL_ONES) && (byte_offset < array_length)) {
            byte_offset++;
            byte = array[byte_offset];
        }
    }
    
    if(byte_offset == array_length)
        return (return_negative_on_not_found ? -1 : byte_offset * 8);
    
    if(!look_for_set_bit)
        byte = (unsigned char)(~byte);
    int int_byte = (int)byte;
    int msb;
    asm("bsrl %1,%0" 
        : "=r"(msb) 
        : "r"(int_byte));
    msb = 7 - msb;
    
    //NSLog(@"returning (%i * 8) + %i; int_byte = %x",byte_offset, msb, int_byte);
    
    return (byte_offset * 8) + msb;
}
