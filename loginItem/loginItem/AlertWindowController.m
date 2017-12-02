//
//  file: AlertWindowController.m
//  project: lulu (login item)
//  description: window controller for main firewall alert
//
//  created by Patrick Wardle
//  copyright (c) 2017 Objective-See. All rights reserved.
//

//TODO: don't show popover if ancestors are nil?

#import <sys/socket.h>
#include <netdb.h>

#import "const.h"
#import "logging.h"
#import "Utilities.h"
#import "AppDelegate.h"
#import "DaemonComms.h"
#import "AlertWindowController.h"

@implementation AlertWindowController

@synthesize alert;
@synthesize signedIcon;
@synthesize processIcon;
@synthesize processName;
@synthesize ancestryButton;
@synthesize ancestryPopover;
@synthesize virusTotalButton;
@synthesize virusTotalPopover;

//center window
// ->also, transparency
-(void)awakeFromNib
{
    //center
    [self.window center];
    
    //full size content view for translucency
    self.window.styleMask = self.window.styleMask | NSWindowStyleMaskFullSizeContentView;
    
    //title bar; translucency
    self.window.titlebarAppearsTransparent = YES;
    
    //move via background
    self.window.movableByWindowBackground = YES;
    
    return;
}

//update alert window
-(void)windowDidChangeOcclusionState:(NSNotification *)notification
{
    //remote addr
    NSString* remoteAddress = nil;
    
    //check occlusion binary flag
    // window going invisble, unset everything
    if(0 == (self.window.occlusionState & NSWindowOcclusionStateVisible))
    {
        //unset icon
        self.processIcon.image = nil;
        
        //unset name
        self.processName.stringValue = @"";
        
        //unset alert msg
        self.alertMessage.stringValue = @"";
        
        //unset process id
        self.processID.stringValue = @"";
        
        //unset process path
        self.processPath.stringValue = @"";
        
        //unset ip address
        self.ipAddress.stringValue = @"";
        
        //unset port & proto
        self.portProto.stringValue = @"";
        
        //alert window maximized?
        // unzoom to bring it back to its default size
        if(YES == self.window.zoomed)
        {
            //reset width (horizontal)
            [self.window.contentView addConstraints: [NSLayoutConstraint constraintsWithVisualFormat:@"H:|[window(0@745)]|"
                                                     options:0 metrics:nil views:NSDictionaryOfVariableBindings(self.window)]];
        }
        
        //make un-modal
        //[[NSApplication sharedApplication] stopModal];
            
        //bail
        goto bail;
    }

    //host name?
    if(nil != self.alert[ALERT_HOSTNAME])
    {
        //use host name
        remoteAddress = self.alert[ALERT_HOSTNAME];
    }
    
    //ip address
    else
    {
        //user ip addr
        remoteAddress = self.alert[ALERT_IPADDR];
    }
    
    /* TOP */
    
    //set process icon
    self.processIcon.image = getIconForProcess(self.alert[ALERT_PATH]);
    
    //set name
    self.processName.stringValue = getProcessName(self.alert[ALERT_PATH]);
    
    //alert message
    self.alertMessage.stringValue = [NSString stringWithFormat:@"is trying to connect to %@", remoteAddress];
    
    /* BOTTOM */
    
    //process pid
    self.processID.stringValue = [self.alert[ALERT_PID] stringValue];
    
    //process path
    self.processPath.stringValue = self.alert[ALERT_PATH];
    
    //ip address
    [self setIPAddress:self.alert[ALERT_IPADDR] withHostname:self.alert[ALERT_HOSTNAME]];
    
    //port & proto
    self.portProto.stringValue = [NSString stringWithFormat:@"%@ (%@)", [self.alert[ALERT_PORT] stringValue], [self convertProtocol]];

    //virus total button
    self.virusTotalButton.enabled = NO;

    [self updateIfLuLuHelperIsAllowed];
    
    /* BOTH */
    
    //process signing info
    // for now, just sets icon
    if(nil != self.alert[ALERT_SIGNINGINFO])
    {
        //process
        [self processSigningInfo];
    }
    
    //make window front
    [NSApp activateIgnoringOtherApps:YES];
    
    //make modal
    [[NSApplication sharedApplication] runModalForWindow:self.window];
    
bail:
    
    return;
}


//window closing
// make sure we're unmodal
- (void)windowWillClose:(NSNotification *)notification
{
    //stop modal
    [[NSApplication sharedApplication] stopModal];
    
    return;
}


//covert number protocol to name
-(NSString*)convertProtocol
{
    //protocol
    NSString* protocol = nil;
    
    //convert
    switch([self.alert[ALERT_PROTOCOL] intValue])
    {
        //tcp
        case SOCK_STREAM:
            
            //set
            protocol = @"TCP";
            
            break;
            
        //udp
        case SOCK_DGRAM:
            
            //set
            protocol = @"UDP";
            
            break;
            
        //??
        default:
            
            //set
            protocol = [NSString stringWithFormat:@"<unknown (%d)>", [self.alert[ALERT_PROTOCOL] intValue]];
    }
    
    return protocol;
}

-(void)performBlockIfLuLuHelperIsAllowd:(void (^)(void))block
{
    //daemon comms object
    DaemonComms* daemonComms = nil;
    
    //init daemom comms
    daemonComms = [[DaemonComms alloc] init];
    
    //get rules from daemon via XPC
    [daemonComms getRules:NO reply:^(NSDictionary* daemonRules)
     {
         NSString* luluHelperPath = NSProcessInfo.processInfo.arguments[0];

         //look for an allow rule for lulu
         for(NSString* processPath in daemonRules.allKeys)
         {
             //is allow rule, match us?
             if( (YES == [processPath isEqualToString:luluHelperPath]) &&
                (RULE_STATE_ALLOW == [[daemonRules[processPath] objectForKey:RULE_ACTION] intValue]) )
             {
                 
                 //dbg msg
                 logMsg(LOG_DEBUG, @"lulu/helper is allowed to access the network");
                 
                 //ok there is a rule for lulu, allowing it
                 // thus, virus total can be queried (i.e. it won't be blocked)
                 block();
                 
                 //done
                 break;
             }
         }
     }];

}

-(void)setIPAddress:(NSString*)ipAddress withHostname:(NSString*)hostname
{
    if (hostname) {
        self.ipAddress.stringValue = [NSString stringWithFormat:@"%@ (%@)", ipAddress, hostname, NULL];
    } else {
        self.ipAddress.stringValue = ipAddress;
    }
}

-(void)updateIfLuLuHelperIsAllowed
{
    [self performBlockIfLuLuHelperIsAllowd:^(void) {
            //lulu allowed/blocked from talking to internet?
            // will fact, will determine state of virus total button
            self.virusTotalButton.enabled = YES;

            if (self.alert[ALERT_HOSTNAME]) {
                return;
            }
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    NSString* ipAddress = self.alert[ALERT_IPADDR];
                    NSString* hostname = [self hostnameForIPAddress:ipAddress
                                                               port:[self.alert[ALERT_PORT] stringValue]
                                                         socketType:[self.alert[ALERT_PROTOCOL] intValue]];
                    [[NSRunLoop mainRunLoop] performInModes:@[NSDefaultRunLoopMode, NSModalPanelRunLoopMode]
                                                      block:^{
                            [self setIPAddress:ipAddress withHostname:hostname];
                        }];
                });
        }];
}

-(NSString*)hostnameForIPAddress:(NSString*)ipAddress port:(NSString*)port socketType:(int)socketType
{
    struct addrinfo hints = { 0 };
    struct addrinfo* addrinfo = NULL;
    char hostname[NI_MAXHOST];
    int flags = NI_NAMEREQD;
    NSString* result = nil;

    hints.ai_family = PF_UNSPEC;
    hints.ai_socktype = socketType;

    if (getaddrinfo([ipAddress UTF8String], [port UTF8String], &hints, &addrinfo) != 0) {
        goto bail;
    }

    if (hints.ai_protocol == IPPROTO_UDP) {
        flags |= NI_DGRAM;
    }

    if (getnameinfo(addrinfo->ai_addr, addrinfo->ai_addrlen,
                    hostname, sizeof(hostname),
                    NULL, 0,
                    flags) != 0) {
        goto bail;
    }

    result = [NSString stringWithUTF8String:hostname];
bail:
    if (addrinfo) {
        freeaddrinfo(addrinfo);
    }
    return result;
}

//set signing icon
// TODO: maybe make this clickable/more info? (signing auths, etc)
-(void)processSigningInfo
{
    //signing info
    NSDictionary* signingInfo = nil;
    
    //extract
    signingInfo = self.alert[ALERT_SIGNINGINFO];
    
    //dbg msg
    logMsg(LOG_DEBUG, [NSString stringWithFormat:@"signing info: %@", signingInfo]);
    
    switch([signingInfo[KEY_SIGNATURE_STATUS] intValue])
    {
        //happily signed
        case noErr:
            
            //item signed by apple
            if(YES == [signingInfo[KEY_SIGNING_IS_APPLE] boolValue])
            {
                //set icon
                signedIcon.image = [NSImage imageNamed:@"signedApple"];
                
                //set details
                //alertInfo[@"processSigning"] = @"Apple Code Signing Cert Auth";
            }
            //signed by dev id/ad hoc, etc
            else
            {
                //set icon
                signedIcon.image = [NSImage imageNamed:@"signed"];
                
                /*
                 
                //set signing auth
                if(0 != [signingInfo[KEY_SIGNING_AUTHORITIES] count])
                {
                    //add code-signing auth
                    alertInfo[@"processSigning"] = [signingInfo[KEY_SIGNING_AUTHORITIES] firstObject];
                }
                //no auths
                else
                {
                    //no auths
                    alertInfo[@"processSigning"] = @"no signing authorities (ad hoc?)";
                }
                */
            }
            
            break;
            
        //unsigned
        case errSecCSUnsigned:
            
            //set icon
            signedIcon.image = [NSImage imageNamed:@"unsigned"];
            
            //set details
            //alertInfo[@"processSigning"] = @"unsigned";
            
            break;
            
        default:
            
            //set icon
            signedIcon.image = [NSImage imageNamed:@"unknown"];
            
            //set details
            //alertInfo[@"processSigning"] = [NSString stringWithFormat:@"unknown (status/error: %ld)", (long)[signingInfo[KEY_SIGNATURE_STATUS] integerValue]];
    }
    
    return;
}

//automatically invoked when user clicks process vt button
// depending on state, show/populate the popup, or close it
-(IBAction)vtButtonHandler:(id)sender
{
    //view controller
    VirusTotalViewController* popoverVC = nil;
    
    //when button is clicked
    // ->open popover
    if(NSOnState == self.virusTotalButton.state)
    {
        //grab
        popoverVC = (VirusTotalViewController*)self.virusTotalPopover.delegate;
        
        //set name
        popoverVC.itemName = self.processName.stringValue;
        
        //set path
        popoverVC.itemPath = self.processPath.stringValue;
        
        //show popover
        [self.virusTotalPopover showRelativeToRect:[self.virusTotalButton bounds] ofView:self.virusTotalButton preferredEdge:NSMaxYEdge];
    }
    //otherwise
    // ->close popover
    else
    {
        //hide popover
        [self.virusTotalPopover close];
    }
    
    return;
}

//invoked when user clicks process ancestry button
// ->depending on state, show/populate the popup, or close it
-(IBAction)ancestryButtonHandler:(id)sender
{
    //process ancestry
    NSMutableArray* processHierarchy = nil;
    
    //when button is clicked
    // ->open popover
    if(NSOnState == self.ancestryButton.state)
    {
        //get process ancestry
        processHierarchy = generateProcessHierarchy([self.alert[ALERT_PID] unsignedShortValue]);
        
        //add the index value to each process in the hierarchy
        // ->used to populate outline/table
        for(NSUInteger i = 0; i<processHierarchy.count; i++)
        {
            //set index
            processHierarchy[i][@"index"] = [NSNumber numberWithInteger:i];
        }

        //set process hierarchy
        self.ancestryViewController.processHierarchy = processHierarchy;
        
        //dynamically (re)size popover
        [self setPopoverSize];
        
        //reload it
        [self.ancestryOutline reloadData];
        
        //auto-expand
        [self.ancestryOutline expandItem:nil expandChildren:YES];
        
        //show popover
        [self.ancestryPopover showRelativeToRect:[self.ancestryButton bounds] ofView:self.ancestryButton preferredEdge:NSMaxYEdge];
    }
    //otherwise
    // ->close popover
    else
    {
        //hide popover
        [self.ancestryPopover close];
    }
    
    return;
}

//set the popover window size
// ->make it roughly fit to content :)
-(void)setPopoverSize
{
    //popover's frame
    CGRect popoverFrame = {0};
    
    //required height
    CGFloat popoverHeight = 0.0f;
    
    //text of current row
    NSString* currentRow = nil;
    
    //width of current row
    CGFloat currentRowWidth = 0.0f;
    
    //length of max line
    CGFloat maxRowWidth = 0.0f;
    
    //extra rows
    NSUInteger extraRows = 0;
    
    //when hierarchy is less than 4
    // ->set (some) extra rows
    if(self.ancestryViewController.processHierarchy.count < 4)
    {
        //5 total
        extraRows = 4 - self.ancestryViewController.processHierarchy.count;
    }
    
    //calc total window height
    // ->number of rows + extra rows, * height
    popoverHeight = (self.ancestryViewController.processHierarchy.count + extraRows + 2) * [self.ancestryOutline rowHeight];
    
    //get window's frame
    popoverFrame = self.ancestryView.frame;
    
    //calculate max line width
    for(NSUInteger i=0; i<self.ancestryViewController.processHierarchy.count; i++)
    {
        //generate text of current row
        currentRow = [NSString stringWithFormat:@"%@ (pid: %@)", self.ancestryViewController.processHierarchy[i][@"name"], [self.ancestryViewController.processHierarchy lastObject][@"pid"]];
        
        //calculate width
        // ->first w/ indentation
        currentRowWidth = [self.ancestryOutline indentationPerLevel] * (i+1);
        
        //calculate width
        // ->then size of string in row
        currentRowWidth += [currentRow sizeWithAttributes: @{NSFontAttributeName: self.ancestryTextCell.font}].width;
        
        //save it greater than max
        if(maxRowWidth < currentRowWidth)
        {
            //save
            maxRowWidth = currentRowWidth;
        }
    }
    
    //add some padding
    // ->scroll bar, etc
    maxRowWidth += 50;
    
    //set height
    popoverFrame.size.height = popoverHeight;
    
    //set width
    popoverFrame.size.width = maxRowWidth;
    
    //set new frame
    self.ancestryView.frame = popoverFrame;
    
    return;
}


//logic to close/remove popups from view
// ->needed, otherwise random memory issues occur :/
-(void)deInitPopup
{
    //virus total popup
    if(NSOnState == self.virusTotalButton.state)
    {
        //close
        [self.virusTotalPopover close];
    
        //set button state to off
        self.virusTotalButton.state = NSOffState;
    }
    
    //process ancestry popup
    if(NSOnState == self.ancestryButton.state)
    {
        //close
        [self.ancestryPopover close];
        
        //set button state to off
        self.ancestryButton.state = NSOffState;
    }
    
    return;
}

//button handler
// ->block/allow, and then close
-(IBAction)handleUserResponse:(id)sender
{
    //alert response
    NSMutableDictionary* response = nil;
    
    //daemon comms object
    DaemonComms* daemonComms = nil;
    
    //init response with initial alert
    response = [NSMutableDictionary dictionaryWithDictionary:self.alert];
    
    //init daemon
    // use local var here, as iVar blocks
    daemonComms = [[DaemonComms alloc] init];
    
    //block
    if(RULE_STATE_BLOCK == ((NSButton*)sender).tag)
    {
        //dbg msg
        logMsg(LOG_DEBUG, @"user clicked 'block'");
        
        //add action, block
        response[ALERT_ACTION] = [NSNumber numberWithInt:RULE_STATE_BLOCK];
    }
    
    //allow
    else
    {
        //dbg msg
        logMsg(LOG_DEBUG, @"user clicked 'allow'");
        
        //add action, allow
        response[ALERT_ACTION] = [NSNumber numberWithInt:RULE_STATE_ALLOW];
    }
    
    //add current user
    response[ALERT_USER] = [NSNumber numberWithUnsignedInteger:getuid()];
    
    //dbg msg
    logMsg(LOG_DEBUG, [NSString stringWithFormat:@"responding to deamon with: %@", response]);
    
    //send response to daemon
    [daemonComms alertResponse:response];
    
    //ensure popups are closed
    [self deInitPopup];
    
    //close window
    [self.window close];
    
    return;
}


@end
