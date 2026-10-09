//=============================================================================
// File:        iosplatform.mm
//
// Description: iOS specific platform support
//=============================================================================

#import <AVFoundation/AVFoundation.h>

#include <main/iosplatform.h>

void iOSInitializeAudioSession()
{
    //
    // The default category is muted by the silent mode switch, use the
    // playback category so the game is heard like other games
    //
    AVAudioSession* session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback error:nil];
    [session setActive:YES error:nil];
}
