//
//  controller.swift
//  Selfde
//

import Foundation

public enum ControllerError: Error {
    case threadLaunchFailure
    case machKernelError(code: Int, message: String)
    case invalidBreakpoint
    case invalidRunState
    case invalidRegisterID
    case invalidRegisterSetID
    case registerBufferIsTooSmall
    case invalidAllocation
}

public enum ControllerEvent {
    case caughtException(Exception)
    case interrupted
}

public typealias ThreadID = UInt64

public struct Breakpoint {
    // Breakpoint's address.
    public let address: OpaquePointer

    public init(address: OpaquePointer) {
        self.address = address
    }
}

// Read/Write/Execute memory permissions.
public struct MemoryPermissions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let Read = MemoryPermissions(rawValue: 1)
    public static let Write = MemoryPermissions(rawValue: 2)
    public static let Execute = MemoryPermissions(rawValue: 4)
}

// Thread's run state.
public enum RunState {
    case running
    case stopped
    case waiting
    case uninterruptible
    case halted
}

/// Launches the controller thread.
public func runSelfdeController(_ client: (Controller) -> (), errorCallback: (Error) -> ()) {
    assert(Foundation.Thread.isMainThread)

    class ThreadContext {
        let callback: (Controller) -> ()
        let errorCallback: (Error) -> ()

        init(callback: (Controller) -> (), errorCallback: (Error) -> ()) {
            self.callback = callback
            self.errorCallback = errorCallback
        }
    }

    var controllerThread: pthread_t? = nil
    let context = ThreadContext(callback: client, errorCallback: errorCallback)
    let result = pthread_create(&controllerThread, nil, { (pointer: UnsafeMutablePointer<Void>) in
        let unmanagedContext = Unmanaged<ThreadContext>.fromOpaque(pointer)
        let controller: Controller
        do {
            controller = try Controller()
        } catch {
            let callback = unmanagedContext.takeUnretainedValue().errorCallback
            unmanagedContext.release()
            callback(error)
            return nil
        }
        let callback = unmanagedContext.takeUnretainedValue().callback
        unmanagedContext.release()
        callback(controller)
        return nil
    }, UnsafeMutablePointer(Unmanaged.passRetained(context).toOpaque()))
    if result != 0 {
        errorCallback(ControllerError.threadLaunchFailure)
    }
}
