//
//  controller.swift
//  Selfde
//

import Foundation

public enum ControllerError: ErrorType {
    case ThreadLaunchFailure
    case MachKernelError(code: Int, message: String)
    case BreakpointAlreadyInstalled
    case InvalidBreakpoint
    case InvalidRunState
}

public struct Breakpoint {
    // Breakpoint's address.
    public let address: COpaquePointer
    // The expected value of the IP register after the breakpoint is hit.
    public let expectedHitAddress: COpaquePointer
}

// Thread's run state.
public enum RunState {
    case Running
    case Stopped
    case Waiting
    case Uninterruptible
    case Halted
}

public protocol Thread {
    /// Returns the thread's instruction pointer / program counter.
    func getInstructionPointer() throws -> COpaquePointer

    func setInstructionPointer(address: COpaquePointer) throws

    /// Returns the thread's stack pointer.
    func getStackPointer() throws -> COpaquePointer

    func beginSingleStepMode() throws

    func endSingleStepMode() throws

    /// Suspends this thread.
    func suspend() throws

    /// Resumes this thread.
    func resume() throws

    /// Aborts this thread.
    func abort() throws

    func getRunState() throws -> RunState

    /// An opaque value that identifies this thread.
    var opaqueValue: Int { get }
}

public protocol Controller: class {
    /// Returns all the threads in this process except for the internal selfde threads.
    func getThreads() throws -> [Thread]
    
    /// Suspends all the threads in this process except for the internal selfde threads.
    func suspendThreads() throws

    /// Resumes all the threads in this process except for the internal selfde threads.
    func resumeThreads() throws

    /// Installs a breakpoint at the given location.
    func installBreakpoint(address: COpaquePointer) throws -> Breakpoint

    func removeBreakpoint(breakpoint: Breakpoint) throws
    
    /// The controller thread is paused until an exception occurs.
    func waitForException() throws -> Exception
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
        let controller: MachController
        do {
            controller = try MachController()
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
