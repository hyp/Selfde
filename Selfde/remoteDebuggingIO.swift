//
//  remoteDebuggingIO.swift
//  Selfde
//

import Foundation

public enum RemoteDebuggingIOError: ErrorType {
    case InvalidHostAndPort
    case StreamOpenError
    case ReadError(message: String)
    case WriteError(message: String)
}

public protocol RemoteDebuggingConnection: class {
    // Blocks until some data is read.
    func read() throws -> ArraySlice<UInt8>
    func write(data: ArraySlice<UInt8>) throws
    func close()
}

final class RemoteDebuggingSocketIO: RemoteDebuggingConnection {
    private let readStream: Unmanaged<CFReadStream>
    private let writeStream: Unmanaged<CFWriteStream>
    private var buffer: [UInt8] = [UInt8](count: 1024, repeatedValue: 0)

    private init(readStream: Unmanaged<CFReadStream>, writeStream: Unmanaged<CFWriteStream>) {
        self.readStream = readStream
        self.writeStream = writeStream
    }

    func read() throws -> ArraySlice<UInt8> {
        let readSize = buffer.withUnsafeMutableBufferPointer { (inout ptr: UnsafeMutableBufferPointer<UInt8>) in
            CFReadStreamRead(readStream.takeUnretainedValue(), ptr.baseAddress, 1024)
        }
        guard readSize > 0 else {
            throw RemoteDebuggingIOError.ReadError(message: readSize == 0 ? "Reached stream end" : "Stream disconnected")
        }
        return buffer.prefix(readSize)
    }

    func write(data: ArraySlice<UInt8>) throws {
        var buffer = data
        while !buffer.isEmpty {
            let writtenSize = buffer.withUnsafeBufferPointer {
                CFWriteStreamWrite(writeStream.takeUnretainedValue(), $0.baseAddress, buffer.count)
            }
            guard writtenSize > 0 else {
                throw RemoteDebuggingIOError.WriteError(message: writtenSize == 0 ? "Reached stream capacity" : "Stream disconnected")
            }
            guard writtenSize < buffer.count else {
                return
            }
            buffer = buffer[writtenSize..<buffer.count]
        }
    }

    func close() {
        CFReadStreamClose(readStream.takeUnretainedValue())
        CFWriteStreamClose(writeStream.takeUnretainedValue())
    }

    deinit {
        close()
        readStream.release()
        writeStream.release()
    }
}

public func createRemoteDebuggingSocketConnection(hostAndPort: String) throws -> RemoteDebuggingConnection {
    guard let (host, port) = parseHostAndPort(hostAndPort) else {
        throw RemoteDebuggingIOError.InvalidHostAndPort
    }
    var readStream: Unmanaged<CFReadStream>?
    var writeStream: Unmanaged<CFWriteStream>?
    CFStreamCreatePairWithSocketToHost(nil, host, UInt32(port), &readStream, &writeStream)
    guard let read = readStream, write = writeStream else {
        throw RemoteDebuggingIOError.StreamOpenError
    }
    guard CFReadStreamOpen(read.takeUnretainedValue()) && CFWriteStreamOpen(write.takeUnretainedValue()) else {
        throw RemoteDebuggingIOError.StreamOpenError
    }
    return RemoteDebuggingSocketIO(readStream: read, writeStream: write)
}

// Parse the host and port that LLDB passes.
private func parseHostAndPort(hostAndPort: String) -> (String, Int)? {
    guard let colonIndex = hostAndPort.rangeOfString(":", options: [.BackwardsSearch]) else {
        return nil
    }
    let host = hostAndPort.substringToIndex(colonIndex.startIndex)
    guard let port = Int(hostAndPort.substringFromIndex(colonIndex.endIndex)) else {
        return nil
    }
    return (host, port)
}
