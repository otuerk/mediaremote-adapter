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

    public var onTrackInfoReceived: ((TrackInfo) -> Void)?
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

    public func startListening() {
        guard listeningProcess == nil else {
            print("Listener process is already running.")
            return
        }

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
                let lineData = self.dataBuffer.subdata(in: 0..<range.lowerBound)
                
                // Remove the line and the newline character from the buffer.
                self.dataBuffer.removeSubrange(0..<range.upperBound)
                
                if !lineData.isEmpty {
                    do {
                        let trackInfo = try JSONDecoder().decode(TrackInfo.self, from: lineData)
                        DispatchQueue.main.async {
                            self.onTrackInfoReceived?(trackInfo)
                            self.updatePlaybackTimer(with: trackInfo)
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
                self?.onListenerTerminated?()
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
} 