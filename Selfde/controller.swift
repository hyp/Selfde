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
    case InvalidRegisterID
    case InvalidRegisterSetID
    case RegisterBufferIsTooSmall
    case InvalidAllocation
}

public struct Breakpoint {
    // Breakpoint's address.
    public let address: COpaquePointer
    // The expected value of the IP register after the breakpoint is hit.
    public let expectedHitAddress: COpaquePointer
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

public protocol Thread {
    /// Returns the thread's instruction pointer / program counter.
    func getInstructionPointer() throws -> COpaquePointer

    func setInstructionPointer(address: COpaquePointer) throws

    /// Returns the thread's stack pointer.
    func getStackPointer() throws -> COpaquePointer

    func getRegisterValue(id: UInt32, setID: UInt32, inout dest: [UInt8]) throws -> ArraySlice<UInt8>

    func setRegisterValue(id: UInt32, setID: UInt32, source: ArraySlice<UInt8>) throws

    func getRegisterContext(inout dest: [UInt8]) throws -> ArraySlice<UInt8>

    func setRegisterContext(source: ArraySlice<UInt8>) throws

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
    func getSharedLibraryInfoAddress() throws -> COpaquePointer

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

    /// Allocates memory in this process with the given permissions.
    func allocate(size: Int, permissions: MemoryPermissions) throws -> COpaquePointer

    /// Deallocates the memory that was previously allocated with the `allocate` method.
    func deallocate(address: COpaquePointer) throws
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
