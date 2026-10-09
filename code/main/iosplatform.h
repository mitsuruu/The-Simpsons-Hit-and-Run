//=============================================================================
// File:        iosplatform.h
//
// Description: iOS specific platform support
//=============================================================================

#ifndef IOSPLATFORM_H
#define IOSPLATFORM_H

// Makes the game's audio play even when the device is in silent mode.
// Must be called before the audio device is opened.
void iOSInitializeAudioSession();

#endif // IOSPLATFORM_H
