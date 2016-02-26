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
