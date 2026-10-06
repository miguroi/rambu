import Carbon
import Foundation

@MainActor
public protocol HotKeyRegistering: AnyObject {
    func register(handler: @escaping @Sendable () -> Void) throws
    func unregister()
}

public struct GlobalHotKeyError: Error, CustomStringConvertible, Sendable {
    public let operation: String
    public let status: OSStatus

    public var description: String {
        "Global shortcut \(operation) failed with OSStatus \(status)."
    }
}

@MainActor
public final class GlobalHotKey {
    private let registrar: any HotKeyRegistering
    private var isRegistered = false

    public init(registrar: any HotKeyRegistering = CarbonHotKeyRegistrar()) {
        self.registrar = registrar
    }

    public func register(action: @escaping @MainActor @Sendable () -> Void) throws {
        if isRegistered { unregister() }
        try registrar.register {
            Task { @MainActor in action() }
        }
        isRegistered = true
    }

    public func unregister() {
        guard isRegistered else { return }
        registrar.unregister()
        isRegistered = false
    }
}

@MainActor
public final class CarbonHotKeyRegistrar: HotKeyRegistering, @unchecked Sendable {
    private static let signature: OSType = 0x524D4255 // RMBU
    private static let identifier: UInt32 = 1

    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var action: (@Sendable () -> Void)?

    public init() {}

    public func register(handler: @escaping @Sendable () -> Void) throws {
        unregister()
        action = handler
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                let registrar = Unmanaged<CarbonHotKeyRegistrar>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                Task { @MainActor in registrar.fire() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard installStatus == noErr else {
            action = nil
            throw GlobalHotKeyError(operation: "handler registration", status: installStatus)
        }

        let identifier = EventHotKeyID(
            signature: Self.signature,
            id: Self.identifier
        )
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            UInt32(controlKey | optionKey),
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard registerStatus == noErr else {
            unregister()
            throw GlobalHotKeyError(operation: "registration", status: registerStatus)
        }
    }

    public func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        eventHandler = nil
        action = nil
    }

    private func fire() {
        action?()
    }
}
