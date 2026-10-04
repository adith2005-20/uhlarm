import Foundation
import SwiftData
import Vision

enum StopMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case qr, barcode, nfc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qr: "QR code"
        case .barcode: "Any barcode"
        case .nfc: "NFC tag"
        }
    }

    var subtitle: String {
        switch self {
        case .qr: "Print one, or use any QR you own"
        case .barcode: "Toothpaste, cereal box, coffee bag"
        case .nfc: "A sticker you tap, e.g. on the mirror"
        }
    }

    var symbol: String {
        switch self {
        case .qr: "qrcode"
        case .barcode: "barcode"
        case .nfc: "wave.3.right"
        }
    }

    var scanSymbol: String {
        switch self {
        case .qr: "qrcode.viewfinder"
        case .barcode: "barcode.viewfinder"
        case .nfc: "wave.3.right"
        }
    }

    /// "tag" / "code" / "barcode", for sentences like "Register a different tag".
    var noun: String {
        switch self {
        case .qr: "code"
        case .barcode: "barcode"
        case .nfc: "tag"
        }
    }

    var symbologies: [VNBarcodeSymbology] {
        switch self {
        case .qr:
            [.qr]
        case .barcode, .nfc:
            [.ean8, .ean13, .upce, .code39, .code93, .code128, .itf14, .i2of5, .codabar,
             .dataMatrix, .pdf417, .aztec, .qr]
        }
    }
}

@Model
final class AlarmItem {
    @Attribute(.unique) var id: UUID = UUID()
    var hour: Int = 7
    var minute: Int = 0
    var label: String = ""
    /// Calendar weekdays, 1 = Sunday … 7 = Saturday. Empty means ring once.
    var weekdays: [Int] = []
    var isEnabled: Bool = true
    var gradualVolume: Bool = true
    var vibration: Bool = true
    var methodRaw: String = StopMethod.qr.rawValue
    var codeID: UUID?
    var soundID: String = "sunrise"
    var createdAt: Date = Date()

    init(id: UUID = UUID(), hour: Int, minute: Int) {
        self.id = id
        self.hour = hour
        self.minute = minute
    }

    var method: StopMethod {
        get { StopMethod(rawValue: methodRaw) ?? .qr }
        set { methodRaw = newValue.rawValue }
    }

    func snapshot(code: WakeCode?) -> AlarmSnapshot {
        AlarmSnapshot(
            id: id, hour: hour, minute: minute, label: label, weekdays: weekdays,
            isEnabled: isEnabled, gradualVolume: gradualVolume, vibration: vibration,
            method: method, soundID: soundID,
            codeName: code?.kind == method ? code?.name : nil,
            codeHash: code?.kind == method ? code?.payloadHash : nil
        )
    }
}

/// Something registered to turn alarms off: a QR code, a barcode or an NFC tag.
/// Only a SHA-256 of the scanned payload is stored, never the payload itself.
@Model
final class WakeCode {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = StopMethod.qr.rawValue
    var payloadHash: String?
    var symbology: String?
    /// NFC tags are confirmed once the Shortcuts automation has called the app with this name.
    var isConfirmed: Bool = false
    var createdAt: Date = Date()

    init(name: String, kind: StopMethod, payloadHash: String?, symbology: String?, isConfirmed: Bool) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.payloadHash = payloadHash
        self.symbology = symbology
        self.isConfirmed = isConfirmed
    }

    var kind: StopMethod {
        get { StopMethod(rawValue: kindRaw) ?? .qr }
        set { kindRaw = newValue.rawValue }
    }
}

/// A Sendable copy of an alarm, used by the AlarmKit engine and the ringing flow.
struct AlarmSnapshot: Sendable, Equatable {
    var id: UUID
    var hour: Int
    var minute: Int
    var label: String
    var weekdays: [Int]
    var isEnabled: Bool
    var gradualVolume: Bool
    var vibration: Bool
    var method: StopMethod
    var soundID: String
    var codeName: String?
    var codeHash: String?

    var displayLabel: String { label.isEmpty ? "Alarm" : label }

    var isRepeating: Bool { !weekdays.isEmpty }

    /// True when there is something registered to scan or tap for this alarm.
    var hasCode: Bool { codeName != nil && (method == .nfc || codeHash != nil) }

    func matches(_ code: ScannedCode) -> Bool {
        guard let codeHash else { return false }
        return CodeHash.hash(code) == codeHash
    }

    func matchesTag(named name: String) -> Bool {
        guard method == .nfc, let codeName else { return false }
        return TagName.matches(codeName, name)
    }

    /// Parent ID for the throwaway alarm rung from Diagnostics.
    static let testAlarmID = UUID(uuidString: "00000000-0000-0000-0000-00000000AA01")!

    static func placeholder(id: UUID) -> AlarmSnapshot {
        AlarmSnapshot(id: id, hour: 7, minute: 0, label: id == testAlarmID ? "Test alarm" : "", weekdays: [], isEnabled: false,
                      gradualVolume: false, vibration: true, method: .qr,
                      soundID: SoundLibrary.defaultSoundID, codeName: nil, codeHash: nil)
    }
}

enum TagName {
    static func normalized(_ name: String) -> String {
        var value = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasSuffix(" tag") { value.removeLast(4) }
        return value
    }

    static func matches(_ a: String, _ b: String) -> Bool {
        let left = normalized(a)
        return !left.isEmpty && left == normalized(b)
    }
}
