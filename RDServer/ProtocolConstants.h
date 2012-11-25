//
//  ProtocolConstants.h
//  RDServer
//
//  Created by Rohan Shah on 7/16/12.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#ifndef RDServer_ProtocolConstants_h
#define RDServer_ProtocolConstants_h

#define TIMEOUT 10.0
#define TELNET_MODE YES
#define DONT_CHANGE_RESOLUTION YES
#define PORT 51617
#define PASSWORD @"hello"

#define EOF_STR @"CAKESCAKESCAKESYUMMYCAKESCAKESCAKES"
#define EOF_DATA [EOF_STR dataUsingEncoding:NSUTF8StringEncoding]

#define NOOP_MSG @"NOOP"
#define AUTHENTICATION_REQUEST_MSG @"AREQ"
#define AUTHENTICATE_MSG @"AUTH"
#define CURRENT_RESOLUTION_MSG @"RESN"
#define SCREEN_MSG @"SCRN"
#define SCREEN_RECT_MSG @"RECT"
#define ALL_RECTS_RECEIVED_MSG @"RCVD"

#endif
