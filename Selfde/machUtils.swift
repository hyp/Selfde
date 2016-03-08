//
//  machUtils.swift
//  Selfde
//

import Foundation
import Darwin.Mach

func handleError(error: mach_error_t) throws {
    guard error != KERN_SUCCESS else {
        return
    }
    let message = String.fromCString(mach_error_string(error)) ?? "<no message>"
    throw ControllerError.MachKernelError(code: Int(error), message: message)
}

func handlePosixError(error: Int32) throws {
    if error != 0 {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(error), userInfo: nil)
    }
}
