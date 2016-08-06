//
//  condition.swift
//  Selfde
//

import Foundation

func throwIfNeeded(posixError error: Int32) throws {
    if error != 0 {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(error), userInfo: nil)
    }
}

/// A condition variabel.
final class Condition {
    let mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
    let cond = UnsafeMutablePointer<pthread_cond_t>.allocate(capacity: 1)

    init() throws {
        try throwIfNeeded(posixError: pthread_mutex_init(mutex, nil))
        try throwIfNeeded(posixError: pthread_cond_init(cond, nil))
    }

    deinit {
        pthread_mutex_destroy(mutex)
        pthread_cond_destroy(cond)
        mutex.deinitialize()
        cond.deinitialize()
        mutex.deallocate(capacity: 1)
        cond.deallocate(capacity: 1)
    }

    func lock() {
        pthread_mutex_lock(mutex)
    }

    func unlock() {
        pthread_mutex_unlock(mutex)
    }

    func wait() {
        pthread_cond_wait(cond, mutex)
    }

    func signal() {
        pthread_cond_signal(cond)
    }

    func broadcast() {
        pthread_cond_broadcast(cond)
    }
}
