import AppKit
#if SWIFT_PACKAGE
import DuoFXCore
#endif

@MainActor
protocol EffectSoundPlaying: AnyObject {
    func play(_ cue: LidSound, volume: Double)
    func setVolume(_ volume: Double)
    func stop()
}

@MainActor
final class EffectSoundPlayer: EffectSoundPlaying {
    private let opening = EffectSoundPlayer.load(.opening)
    private let closing = EffectSoundPlayer.load(.closing)

    static func load(_ cue: LidSound) -> NSSound? {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: cue.rawValue, withExtension: "wav", subdirectory: "Sounds")
                ?? bundle.url(forResource: cue.rawValue, withExtension: "wav") else { return nil }
        return NSSound(contentsOf: url, byReference: false)
    }

    func play(_ cue: LidSound, volume: Double) {
        stop()
        setVolume(volume)
        let sound = cue == .opening ? opening : closing
        sound?.currentTime = 0
        sound?.play()
    }

    func setVolume(_ volume: Double) {
        let level = Float(min(max(volume.isFinite ? volume : 0, 0), 1))
        opening?.volume = level; closing?.volume = level
    }

    func stop() { opening?.stop(); closing?.stop() }
}
