import Foundation

public class MediaController {

    private var perlScriptPath: String? {
        guard let path = Bundle.module.path(forResource: "run", ofType: "pl") else {
            assertionFailure("run.pl script not found in bundle resources.")
            return nil
        }
        return path
    }

    private var listeningProcess: Process?
    private var dataBuffer = Data()
    private var playbackTimer: Timer?
    private var playbackInfo: (baseTime: TimeInterval, baseTimestamp: TimeInterval)?
    private var currentTrackIdentifier: String?
    private var isPlaying = false
    private var seekTimer: Timer?
    private var eventCount = 0
    private var restartThreshold = 100 // Restart process every x events to clear memory leak

    public var onTrackInfoReceived: ((TrackInfo?) -> Void)?
    public var onListenerTerminated: (() -> Void)?
    public var onDecodingError: ((Error, Data) -> Void)?
    public var onPlaybackTimeUpdate: ((_ elapsedTime: TimeInterval) -> Void)?
    public var bundleIdentifier: String?

    public init(bundleIdentifier: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
    }

    private var libraryPath: String? {
        let bundle = Bundle(for: MediaController.self)
        guard let path = bundle.executablePath else {
            assertionFailure("Could not locate the executable path for the MediaRemoteAdapter framework.")
            return nil
        }
        return path
    }

    @discardableResult
    private func runPerlCommand(arguments: [String]) -> (output: String?, error: String?, terminationStatus: Int32) {
        guard let scriptPath = perlScriptPath else {
            return (nil, "Perl script not found.", -1)
        }
        guard let libraryPath = libraryPath else {
            return (nil, "Dynamic library path not found.", -1)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [scriptPath, libraryPath] + arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

            return (output, errorOutput, process.terminationStatus)
        } catch {
            return (nil, error.localizedDescription, -1)
        }
    }
    
    /// Returns the track info independently from the actual listen process. Since this is an async operation, the whole setup of the
    /// output reading etc. has to be performed again
    public func getTrackInfo(_ onReceive: @escaping (TrackInfo?) -> Void){
        guard let scriptPath = perlScriptPath else {
            return
        }
        guard let libraryPath = libraryPath else {
            return
        }

        let getListeningProcess = Process()
        getListeningProcess.executableURL = URL(fileURLWithPath: "/usr/bin/perl")

        var getDataBuffer = Data()
        var callbackExecuted = false
        
        var arguments = [scriptPath]
        if let bundleId = bundleIdentifier {
            arguments.append("--id")
            arguments.append(bundleId)
        }
        arguments.append(contentsOf: [libraryPath, "get"])
        getListeningProcess.arguments = arguments

        let outputPipe = Pipe()
        getListeningProcess.standardOutput = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            guard let self = self else { return }

            let incomingData = fileHandle.availableData
            if incomingData.isEmpty {
                // This can happen when the process terminates.
                return
            }

            getDataBuffer.append(incomingData)
            
            // Process all complete lines in the buffer.
            while let range = getDataBuffer.firstRange(of: "\n".data(using: .utf8)!) {
                // Make sure to check ranges
                guard range.lowerBound <= getDataBuffer.count else {
                    break
                }
                
                let lineData = getDataBuffer.subdata(in: 0..<range.lowerBound)
                
                // Remove the line and the newline character from the buffer.
                getDataBuffer.removeSubrange(0..<range.upperBound)
                
                if !lineData.isEmpty {
                    do {
                        let trackInfo = try JSONDecoder().decode(TrackInfo.self, from: lineData)
                        if !callbackExecuted {
                            callbackExecuted = true
                            DispatchQueue.main.async {
                                onReceive(trackInfo)
                            }
                        }
                        return
                    } catch {
                        if !callbackExecuted {
                            callbackExecuted = true
                            DispatchQueue.main.async {
                                onReceive(nil)
                            }
                        }
                        return
                    }
                }
            }
        }
        
        getListeningProcess.terminationHandler = { _ in
            if !callbackExecuted {
                DispatchQueue.main.async {
                    // If we reach here and haven't called onReceive yet, it means no data was available
                    onReceive(nil)
                }
            }
        }

        do {
            try getListeningProcess.run()
        } catch {
        }
    }

    public func startListening() {
        guard listeningProcess == nil else {
            return
        }
        
        eventCount = 0 // Reset event count
        startListeningInternal()
    }
    
    private func startListeningInternal() {
        guard let scriptPath = perlScriptPath else {
            return
        }
        guard let libraryPath = libraryPath else {
            return
        }

        listeningProcess = Process()
        listeningProcess?.executableURL = URL(fileURLWithPath: "/usr/bin/perl")

        var arguments = [scriptPath]
        if let bundleId = bundleIdentifier {
            arguments.append("--id")
            arguments.append(bundleId)
        }
        arguments.append(contentsOf: [libraryPath, "loop"])
        listeningProcess?.arguments = arguments

        let outputPipe = Pipe()
        listeningProcess?.standardOutput = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            guard let self = self else { return }

            let incomingData = fileHandle.availableData
            if incomingData.isEmpty {
                // This can happen when the process terminates.
                return
            }

            self.dataBuffer.append(incomingData)
            
            // Process all complete lines in the buffer.
            while let range = self.dataBuffer.firstRange(of: "\n".data(using: .utf8)!) {
                // Make sure to check ranges
                guard range.lowerBound <= self.dataBuffer.count else {
                    break
                }
                
                let lineData = self.dataBuffer.subdata(in: 0..<range.lowerBound)
                
                // Remove the line and the newline character from the buffer.
                self.dataBuffer.removeSubrange(0..<range.upperBound)
                
                // Check for "NIL" in data value, as this is an indicator that there's currently no
                // mediaplayer at all
                if lineData.count == 3, lineData == "NIL".data(using: .ascii) {
                    self.onTrackInfoReceived?(nil)
                } else if !lineData.isEmpty {
                    // Increment event count and check for restart
                    self.eventCount += 1
                    
                    do {
                        let trackInfo = try JSONDecoder().decode(TrackInfo.self, from: lineData)
                        DispatchQueue.main.async {
                            // Check if we need to restart after processing
                            if self.eventCount >= self.restartThreshold {
                                self.restartListeningProcess()
                            } else {
                                self.onTrackInfoReceived?(trackInfo)
                                self.updatePlaybackTimer(with: trackInfo)
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.onDecodingError?(error, lineData)
                        }
                    }
                }
            }
        }

        listeningProcess?.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.listeningProcess = nil
                self?.playbackTimer?.invalidate()
                // Don't call onListenerTerminated if this is a planned restart
                if self?.eventCount != 0 {
                    self?.onListenerTerminated?()
                }
            }
        }

        do {
            try listeningProcess?.run()
        } catch {
            print("Failed to start listening process: \(error)")
            listeningProcess = nil
        }
    }

    public func stopListening() {
        listeningProcess?.terminate()
        playbackTimer?.invalidate()
        listeningProcess = nil
    }

    public func play() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["play"])
        }
    }

    public func pause() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["pause"])
        }
    }

    public func togglePlayPause() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["toggle_play_pause"])
        }
    }

    public func nextTrack() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["next_track"])
        }
    }

    public func previousTrack() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["previous_track"])
        }
    }
    
    public func stop() {
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPerlCommand(arguments: ["stop"])
        }
    }

    public func setTime(seconds: Double) {
        seekTimer?.invalidate()

        // Optimistically update the UI and our internal timer state.
        onPlaybackTimeUpdate?(seconds)
        self.playbackInfo = (baseTime: seconds, baseTimestamp: Date().timeIntervalSince1970)

        // If we are currently playing, ensure the timer continues to run from the new
        // optimistic position for a smooth UI experience during scrubbing.
        if isPlaying, playbackTimer == nil || !playbackTimer!.isValid {
            playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                self?.handleTimerTick()
            }
        }

        // Throttle the actual seek command to avoid overwhelming the system.
        seekTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
            DispatchQueue.global(qos: .userInitiated).async {
                self?.runPerlCommand(arguments: ["set_time", String(seconds)])
            }
        }
    }
    
    private func updatePlaybackTimer(with trackInfo: TrackInfo) {
        let newTrackIdentifier = trackInfo.payload.uniqueIdentifier
        
        // When a new track is detected, reset the progress to 0.
        if newTrackIdentifier != self.currentTrackIdentifier {
            self.currentTrackIdentifier = newTrackIdentifier
            onPlaybackTimeUpdate?(0)
        }

        playbackTimer?.invalidate()

        // Update our local playing state.
        self.isPlaying = trackInfo.payload.isPlaying ?? false

        guard self.isPlaying,
              let baseTime = trackInfo.payload.elapsedTimeMicros,
              let baseTimestamp = trackInfo.payload.timestampEpochMicros
        else {
            if let lastKnownTime = trackInfo.payload.elapsedTimeMicros {
                onPlaybackTimeUpdate?(lastKnownTime / 1_000_000)
            }
            return
        }

        self.playbackInfo = (baseTime: baseTime / 1_000_000,
                               baseTimestamp: baseTimestamp / 1_000_000)

        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.handleTimerTick()
        }
    }

    @objc private func handleTimerTick() {
        guard let info = playbackInfo else { return }
        let now = Date().timeIntervalSince1970
        let timePassed = now - info.baseTimestamp
        let currentElapsedTime = info.baseTime + timePassed
        onPlaybackTimeUpdate?(currentElapsedTime)
    }
    
    private func restartListeningProcess() {
        // Stop current process
        listeningProcess?.terminate()
        listeningProcess = nil
        
        // Clear data buffer to free any accumulated data
        dataBuffer.removeAll()
        
        // Reset event count
        eventCount = 0
        
        // Wait a brief moment for cleanup, then restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.startListeningInternal()
        }
    }
} 
