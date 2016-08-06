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
