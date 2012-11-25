//
//  RectArray.h
//  RDServer
//
//  Created by Rohan Shah on 8/7/12.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

typedef struct _RectArray {
    CGRect *array;
    CGRectCount count;
    unsigned int capacity;
    unsigned int retainCount;
} RectArray;
