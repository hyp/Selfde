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
    case invalidAddress
}

public enum ControllerEvent {
    case caughtException(Exception)
    case interrupted
}

/// Launches the controller thread.
public func runSelfdeController(_ client: @escaping (Controller) -> (), errorCallback: @escaping (Error) -> ()) {
    assert(Foundation.Thread.isMainThread)

    class ThreadContext {
        let callback: (Controller) -> ()
        let errorCallback: (Error) -> ()

        init(callback: @escaping (Controller) -> (), errorCallback: @escaping (Error) -> ()) {
            self.callback = callback
            self.errorCallback = errorCallback
        }
    }

    var controllerThread: pthread_t? = nil
    let context = ThreadContext(callback: client, errorCallback: errorCallback)
    let result = pthread_create(&controllerThread, nil, { pointer in
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
    }, Unmanaged.passRetained(context).toOpaque())
    if result != 0 {
        errorCallback(ControllerError.threadLaunchFailure)
    }
}
