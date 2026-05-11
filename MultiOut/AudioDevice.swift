import Foundation
import CoreAudio

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let canSetVolume: Bool
    let transportType: UInt32

    var isBluetooth: Bool {
        transportType == kAudioDeviceTransportTypeBluetooth ||
        transportType == kAudioDeviceTransportTypeBluetoothLE
    }

    var symbolName: String {
        switch transportType {
        case kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE:
            return "dot.radiowaves.left.and.right"
        case kAudioDeviceTransportTypeUSB:
            return "externaldrive"
        case kAudioDeviceTransportTypeBuiltIn:
            return "waveform"
        case kAudioDeviceTransportTypeHDMI,
             kAudioDeviceTransportTypeDisplayPort:
            return "display"
        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"
        case kAudioDeviceTransportTypeThunderbolt:
            return "bolt.fill"
        default:
            return "speaker.fill"
        }
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: AudioDevice, rhs: AudioDevice) -> Bool { lhs.id == rhs.id }
}
