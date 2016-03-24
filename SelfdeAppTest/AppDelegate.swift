//
//  AppDelegate.swift
//  SelfdeAppTest
//

import Cocoa
import Selfde

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet weak var window: NSWindow!

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        runSelfDebuggerTest()
        exit(0)
    }
}

func runSelfDebuggerTest() {
    var output = ""
    func print(s: String) {
        Swift.print(s)
        output.write(s + "\n")
    }

    // Main thread info.
    let mainThread: Thread
    do {
        mainThread = try getCurrentThread()
    } catch {
        fatalError("No main thread?")
    }
    print("Main thread: \(mainThread.threadID)")
    // Used to signal the main thread that the breakpoint is installed.
    let semaphore = dispatch_semaphore_create(0)
    let breakpointAddress = COpaquePointer(getTestFunctionAddress())

    runSelfdeController ({ controller in
        print("Reached callback")
        do {
            try controller.initializeExceptionHandlingForThreads(try controller.getThreads())
            let sharedLibAddress = try controller.getSharedLibraryInfoAddress()
            print("Got shared lib address \(sharedLibAddress)")
            let threads = try controller.getThreads()
            var mainBreakpoint: Breakpoint?
            for thread in threads  {
                let id = thread.threadID
                let ip = try thread.getInstructionPointer()
                let sp = try thread.getStackPointer()
                print("  Thread \(id): ip = \(ip), sp = \(sp)")
                if thread == mainThread { // FIXME: this is a HACK.
                    mainBreakpoint = try controller.installBreakpoint(breakpointAddress)
                    if mainBreakpoint!.address != breakpointAddress {
                        fatalError()
                    }
                }
            }
            guard let breakpoint = mainBreakpoint else {
                fatalError()
            }
            sleep(2)
            dispatch_semaphore_signal(semaphore)

            guard case .CaughtException(let exception) = try controller.waitForEvent() else {
                fatalError("Not an exception")
            }
            if exception.thread != mainThread {
                fatalError("Exception isn't on the main thread!")
            }
            let hitIP = try exception.thread.getInstructionPointer()
            guard exception.isBreakpoint && exception.reason == "breakpoint" else {
                fatalError("Not a breakpoint!")
            }
            guard hitIP == breakpoint.address else {
                fatalError("Unexpected hit address!")
            }
            print("Caught the breakpoint, thread = \(exception.thread.threadID), ip = \(hitIP), type = \(exception.type)")
            // Remove the breakpoint and resume the thread.
            try controller.removeBreakpoint(breakpoint)
            try exception.thread.beginSingleStepMode()
            try exception.thread.resume()

            guard case .CaughtException(let exception2) = try controller.waitForEvent() else {
                fatalError("Not an exception")
            }
            let hitIP2 = try exception2.thread.getInstructionPointer()
            guard hitIP2 != breakpoint.address else {
                fatalError("Unexpected hit address!")
            }
            print("Caught the single step past the original instruction, thread = \(exception2.thread.threadID), ip = \(hitIP2), type = \(exception2.type)")
            // Restore the breakpoint
            if exception.thread != exception2.thread {
                fatalError("Invalid thread!")
            }
            let breakpoint2 = try controller.installBreakpoint(breakpointAddress)
            try exception2.thread.endSingleStepMode()
            try exception2.thread.resume()

            // Remove the breakpoint and resume the thread.
            guard case .CaughtException(let exception3) = try controller.waitForEvent() else {
                fatalError("Not an exception")
            }
            let hitIP3 = try exception3.thread.getInstructionPointer()
            guard hitIP3 == breakpoint2.address else {
                fatalError("Unexpected hit address!")
            }
            print("Caught the breakpoint again, thread = \(exception3.thread.threadID), ip = \(hitIP3), type = \(exception3.type)")
            // Remove the breakpoint and resume the thread.
            try controller.removeBreakpoint(breakpoint2)
            try exception3.thread.resume()

            print("Controller done!")
        } catch {
            print("\(error)")
            fatalError()
        }
        }, errorCallback: { error in
            print("Error: \(error)")
            fatalError()
    })

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
    print("Main thread running code")
    testFunction()
    print("Main thread ran once")
    testFunction()
    print("Main thread done running!")

    let result = output.containsString("Reached callback") &&
        output.containsString("Main thread running code") &&
        output.containsString("Caught the breakpoint") &&
        output.containsString("Caught the single step past the original instruction") &&
        output.containsString("Main thread ran once") &&
        output.containsString("Caught the breakpoint again") &&
        output.containsString("Controller done") &&
        output.containsString("Main thread done running")
    guard result == true else {
        fatalError("Test failed")
    }
}
