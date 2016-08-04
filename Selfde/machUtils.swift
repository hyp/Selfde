//
//  machUtils.swift
//  Selfde
//

import Foundation
import Darwin.Mach

func handleError(_ error: mach_error_t) throws {
    guard error != KERN_SUCCESS else {
        return
    }
    let message = String(cString: mach_error_string(error)) ?? "<no message>"
    throw ControllerError.machKernelError(code: Int(error), message: message)
}

func handlePosixError(_ error: Int32) throws {
    if error != 0 {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(error), userInfo: nil)
    }
}
