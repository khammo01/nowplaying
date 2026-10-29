import Foundation
import CoreAudio
func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}
func fail(_ text: String) -> Never { fputs(text + "\n", stderr); exit(1) }
let lockPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("NowPlaying/cache/hidock-volume.lock").path
let lockFD = open(lockPath, O_CREAT | O_RDWR, 0o600)
guard lockFD >= 0, flock(lockFD, LOCK_EX) == 0 else { fail("Cannot lock HiDock volume control") }
defer { flock(lockFD, LOCK_UN); close(lockFD) }
var a = address(kAudioHardwarePropertyDevices)
var size: UInt32 = 0
guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { fail("Cannot list audio devices") }
var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &devices) == noErr else { fail("Cannot read audio devices") }
for device in devices {
    var name: CFString = "" as CFString
    var n = UInt32(MemoryLayout<CFString>.size)
    var key = address(kAudioObjectPropertyName)
    guard AudioObjectGetPropertyData(device, &key, 0, nil, &n, &name) == noErr, (name as String) == "HiDock H1" else { continue }
    var levels: [(AudioObjectPropertyAddress, Float32)] = []
    for element: AudioObjectPropertyElement in [0, 1, 2] {
        var v = address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, element)
        var settable: DarwinBoolean = false
        var level: Float32 = 0
        var bytes = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectHasProperty(device, &v), AudioObjectIsPropertySettable(device, &v, &settable) == noErr, settable.boolValue,
           AudioObjectGetPropertyData(device, &v, 0, nil, &bytes, &level) == noErr {
            levels.append((v, level))
            if element == 0 { break }
        }
    }
    guard !levels.isEmpty else { continue }
    let argument = CommandLine.arguments.dropFirst().first ?? "--read"
    if argument != "--read" {
        guard let delta = Float32(argument), delta.isFinite, abs(delta) <= 10 else { fail("Expected --read or a delta from -10 to 10 percent") }
        for (var property, old) in levels {
            var value = min(1, max(0, old + delta / 100))
            guard AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr else { fail("Cannot set HiDock H1 output volume") }
        }
    }
    var property = levels[0].0
    var value: Float32 = 0
    var bytes = UInt32(MemoryLayout<Float32>.size)
    guard AudioObjectGetPropertyData(device, &property, 0, nil, &bytes, &value) == noErr else { fail("Cannot verify HiDock H1 volume") }
    print(Int((value * 100).rounded()))
    exit(0)
}
fail("HiDock H1 with adjustable output volume was not found")
