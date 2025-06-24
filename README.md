# MediaRemoteAdapter

A Swift package for macOS that provides a robust, modern interface for controlling media playback and receiving track information, designed to work around the sandboxing and entitlement restrictions of the private `MediaRemote.framework`.

## How It Works
This package uses a unique architecture to gain the necessary permissions for media control:

1.  **Swift `MediaController`:** The public API you interact with in your app. It's a simple, modern Swift class.
2.  **Objective-C Bridge:** An internal library containing the code that calls the private `MediaRemote.framework` functions.
3.  **Perl Interpreter:** The `MediaController` does not call the Objective-C code directly. Instead, it executes a bundled Perl script using the system's `/usr/bin/perl`, which has the necessary entitlements to access the media service.
4.  **Dynamic Loading:** At runtime, the Perl script dynamically loads the compiled Objective-C library, acting as a sandboxed bridge. It passes commands in from your app and streams track data back out over a pipe.

This approach provides the power of the private framework with the safety and convenience of a modern Swift Package.

<img src="https://github.com/user-attachments/assets/ddb17380-37fd-4b63-803e-b82f616db48d" alt="drawing" width="400"/>

## Installation

You can add `MediaRemoteAdapter` to your project using the Swift Package Manager.

1.  In Xcode, open your project and navigate to **File > Add Packages...**
2.  Enter the repository URL: `https://github.com/ejbills/mediaremote-adapter.git`
3.  Choose the `MediaRemoteAdapter` product and add it to your application's target.

### Important: Embedding the Framework

After adding the package, you must ensure the framework is correctly embedded and signed.

1.  In the Project Navigator, select your project, then select your main application target.
2.  Go to the **General** tab.
3.  Find the **"Frameworks, Libraries, and Embedded Content"** section.
4.  `MediaRemoteAdapter.framework` should be listed. Change its setting from "Do Not Embed" to **"Embed & Sign"**.

This crucial step copies the framework into your app and signs it with your developer identity, as required by macOS.

## Usage

### Basic Example

Here is a basic example of how to use `MediaController`.

```swift
import MediaRemoteAdapter
import Foundation
import AppKit

class YourAppController {
    let mediaController = MediaController()
    var currentTrackDuration: TimeInterval = 0

    init() {
        // Handle incoming track data
        mediaController.onTrackInfoReceived = { trackInfo in
            print("Now Playing: \(trackInfo.payload.title ?? "N/A")")
            self.currentTrackDuration = (trackInfo.payload.durationMicros ?? 0) / 1_000_000
            
            if let artworkImage = trackInfo.payload.artwork {
                // Use your image here...
            }
        }
        
        // Handle playback time updates for your UI
        // WARNING: This handler is for demonstration only. It uses a polling
        // mechanism that can lead to high CPU usage and is not recommended for
        // production environments. The timer is an estimate.
        mediaController.onPlaybackTimeUpdate = { elapsedTime in
            let percentage = self.currentTrackDuration > 0 ? (elapsedTime / self.currentTrackDuration) * 100 : 0
            print(String(format: "Progress: %.2f%%", percentage))
            // Update your progress bar here
        }

        // Optionally handle cases where JSON decoding fails
        mediaController.onDecodingError = { error, data in
            print("Failed to decode JSON: \(error)")
        }

        // Handle listener termination
        mediaController.onListenerTerminated = {
            print("MediaRemoteAdapter listener process was terminated.")
        }
    }

    func setupAndStart() {
        // Start listening for media events in the background.
        mediaController.startListening()
    }

    // All playback commands are asynchronous.
    func play() { mediaController.play() }
    func pause() { mediaController.pause() }
    func togglePlayPause() { mediaController.togglePlayPause() }
    func nextTrack() { mediaController.nextTrack() }
    func previousTrack() { mediaController.previousTrack() }
    func stop() { mediaController.stop() }
    
    func seek(to seconds: Double) {
        mediaController.setTime(seconds: seconds)
    }
}
```

### Filtering by Application

You can create a `MediaController` that only listens for events from a specific application by providing its bundle identifier during initialization. This is useful for creating separate views or controllers for different media apps.

```swift
// Controller that only receives events from Apple Music
let musicController = MediaController(bundleIdentifier: "com.apple.Music")
musicController.onTrackInfoReceived = { data in
    // This will only be called for Apple Music events
}
musicController.startListening()

// Controller that only receives events from Spotify
let spotifyController = MediaController(bundleIdentifier: "com.spotify.client")
spotifyController.onTrackInfoReceived = { data in
    // This will only be called for Spotify events
}
spotifyController.startListening()
```

### Controlling Specific Applications

The `MediaRemote` framework sends playback commands to whichever application the system currently considers the "Now Playing" app. **You cannot target a command to a specific background application.**

To control a specific app (e.g., Spotify), you must first make it the active media source. This is typically done through user interaction (like pressing play in the app's window) or programmatically via AppleScript.

For example, you can use `osascript` from the command line to tell an app to play, which brings it to the forefront of media control:
```sh
osascript -e 'tell application "Music" to play'
```
After this, any calls like `mediaController.pause()` will be directed to Music.

## API Overview

### `MediaController(bundleIdentifier: String? = nil)`
Initializes a new controller. If `bundleIdentifier` is provided, the controller will only receive notifications from the application with that ID.

### `var bundleIdentifier: String?`
The bundle identifier of the application to filter events from. This can be set after initialization, but will only take effect the next time `startListening()` is called.

### `var onTrackInfoReceived: ((TrackInfo) -> Void)?`
A closure that is called whenever new track information is available. It provides a decoded `TrackInfo` object, which contains all track metadata and a computed `artwork` property of type `NSImage?`.

### `var onPlaybackTimeUpdate: ((_ elapsedTime: TimeInterval) -> Void)?`
A closure that provides a continuous stream of the current track's elapsed time in seconds. It fires multiple times per second while a track is playing and provides a final update when it's paused. This is ideal for updating UI elements like a progress bar.

> **Note:** The playback timer is an estimate and not guaranteed to be perfectly accurate. Due to its reliance on frequent polling, this feature can cause high CPU usage and is therefore not recommended for prolonged use in production environments where performance is critical.

### `var onDecodingError: ((Error, Data) -> Void)?`
An optional closure that is called if the incoming JSON data from the listener process cannot be decoded into a `TrackInfo` object. This can be useful for debugging or handling unexpected data structures.

### `var onListenerTerminated: (() -> Void)?`
A closure that is called if the background listener process terminates unexpectedly. You may want to restart it here.

### `startListening()`
Spawns the background Perl process to begin listening for media events.

### `stopListening()`
Terminates the background listener process.

### Playback Commands
These functions send an asynchronous command to the background process.
- `play()`
- `pause()`
- `togglePlayPause()`
- `nextTrack()`
- `previousTrack()`
- `stop()`
- `setTime(seconds: Double)`

## Acknowledgements

This project is a Swift-based implementation heavily inspired by the original Objective-C project, [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter). The core technique of using a Perl script to bypass framework restrictions was pioneered in that repository.

## License

This project is licensed under the BSD 3-Clause License. See the [LICENSE](LICENSE) file for details.
