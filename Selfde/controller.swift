//
//  controller.swift
//  Selfde
//

import Foundation

public enum ControllerError: ErrorType {
    case ThreadLaunchFailure
    case MachKernelError(code: Int, message: String)
    case InvalidBreakpoint
    case InvalidRunState
    case InvalidRegisterID
    case InvalidRegisterSetID
    case RegisterBufferIsTooSmall
    case InvalidAllocation
}

public typealias ThreadID = UInt64

public struct Breakpoint {
    // Breakpoint's address.
    public let address: COpaquePointer

    public init(address: COpaquePointer) {
        self.address = address
    }
}

// Read/Write/Execute memory permissions.
public struct MemoryPermissions: OptionSetType {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = 0 }

    public static let Read = MemoryPermissions(rawValue: 1)
    public static let Write = MemoryPermissions(rawValue: 2)
    public static let Execute = MemoryPermissions(rawValue: 4)
}

// Thread's run state.
public enum RunState {
    case Running
    case Stopped
    case Waiting
    case Uninterruptible
    case Halted
}

/// Launches the controller thread.
public func runSelfdeController(client: Controller -> (), errorCallback: ErrorType -> ()) {
    assert(NSThread.isMainThread())

    class ThreadContext {
        let callback: Controller -> ()
        let errorCallback: ErrorType -> ()

        init(callback: Controller -> (), errorCallback: ErrorType -> ()) {
            self.callback = callback
            self.errorCallback = errorCallback
        }
    }

    var controllerThread: pthread_t = nil
    let context = ThreadContext(callback: client, errorCallback: errorCallback)
    let result = pthread_create(&controllerThread, nil, { (pointer: UnsafeMutablePointer<Void>) in
        let unmanagedContext = Unmanaged<ThreadContext>.fromOpaque(COpaquePointer(pointer))
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
        errorCallback(ControllerError.ThreadLaunchFailure)
    }
}
