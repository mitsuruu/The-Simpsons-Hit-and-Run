//=============================================================================
// File:        iosplatform.h
//
// Description: iOS specific platform support
//=============================================================================

#ifndef IOSPLATFORM_H
#define IOSPLATFORM_H

struct SDL_Window;

// Makes the game's audio play even when the device is in silent mode.
// Must be called before the audio device is opened.
void iOSInitializeAudioSession();

// Shows touch controls while no physical gamepad is connected. Must be called
// on the main thread after the GL context has been created, creating it
// replaces the view of the window.
void iOSInitializeTouchControls( SDL_Window* window );

#endif // IOSPLATFORM_H
