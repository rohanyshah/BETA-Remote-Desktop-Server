//
//  pngquant.h
//  RDServer
//
//  Created by Rohan Shah on 7/4/12.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

#ifndef RDServer_pngquant_h
#define RDServer_pngquant_h

typedef enum {
    SUCCESS = 0,
    READ_ERROR = 2,
    TOO_MANY_COLORS = 5,
    NOT_OVERWRITING_ERROR = 15,
    CANT_WRITE_ERROR = 16,
    OUT_OF_MEMORY_ERROR = 17,
    PNG_OUT_OF_MEMORY_ERROR = 24,
    INIT_OUT_OF_MEMORY_ERROR = 34,
    INTERNAL_LOGIC_ERROR = 18,
    BAD_SIGNATURE_ERROR = 21,
    LIBPNG_FATAL_ERROR = 25,
    LIBPNG_INIT_ERROR = 35,
    LIBPNG_WRITE_ERROR = 55,
    LIBPNG_WRITE_WHOLE_ERROR = 45,
} pngquant_error;

pngquant_error new_pngquant(const void *image, NSData **buffer, int floyd, int reqcolors, int ie_bug);

#endif
