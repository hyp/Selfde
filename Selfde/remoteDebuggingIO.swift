//
//  remoteDebuggingIO.swift
//  Selfde
//

import Foundation

public enum RemoteDebuggingIOError: Error {
    case invalidHostAndPort
    case streamOpenError
    case readError(message: String)
    case writeError(message: String)
}

public protocol RemoteDebuggingReader: class {
    // Blocks until some data is read.
    func read() throws -> ArraySlice<UInt8>
    func close()
}

public protocol RemoteDebuggingWriter: class {
    func write(data: ArraySlice<UInt8>) throws
    func close()
}

private final class RemoteDebuggingSocketReader: RemoteDebuggingReader {
    let readStream: Unmanaged<CFReadStream>
    var buffer: [UInt8] = [UInt8](repeating: 0, count: 1024)

    init(readStream: Unmanaged<CFReadStream>) {
        self.readStream = readStream
    }

    func read() throws -> ArraySlice<UInt8> {
        let readSize = buffer.withUnsafeMutableBufferPointer { (ptr: inout UnsafeMutableBufferPointer<UInt8>) in
            CFReadStreamRead(readStream.takeUnretainedValue(), ptr.baseAddress, 1024)
        }
        guard readSize > 0 else {
            throw RemoteDebuggingIOError.readError(message: readSize == 0 ? "Reached stream end" : "Stream disconnected")
        }
        return buffer.prefix(readSize)
    }

    func close() {
        CFReadStreamClose(readStream.takeUnretainedValue())
    }

    deinit {
        close()
        readStream.release()
    }
}

private final class RemoteDebuggingSocketWriter: RemoteDebuggingWriter {
    let writeStream: Unmanaged<CFWriteStream>

    init(writeStream: Unmanaged<CFWriteStream>) {
        self.writeStream = writeStream
    }

    func write(data: ArraySlice<UInt8>) throws {
        var buffer = data
        while !buffer.isEmpty {
            let writtenSize = buffer.withUnsafeBufferPointer {
                CFWriteStreamWrite(writeStream.takeUnretainedValue(), $0.baseAddress, buffer.count)
            }
            guard writtenSize > 0 else {
                throw RemoteDebuggingIOError.writeError(message: writtenSize == 0 ? "Reached stream capacity" : "Stream disconnected")
            }
            guard writtenSize < buffer.count else {
                return
            }
            buffer = buffer[writtenSize..<buffer.count]
        }
    }

    func close() {
        CFWriteStreamClose(writeStream.takeUnretainedValue())
    }

    deinit {
        close()
        writeStream.release()
    }
}

public func createRemoteDebuggingSocketConnection(_ hostAndPort: String) throws -> (RemoteDebuggingReader, RemoteDebuggingWriter) {
    guard let (host, port) = parseHostAndPort(hostAndPort) else {
        throw RemoteDebuggingIOError.invalidHostAndPort
    }
    var readStream: Unmanaged<CFReadStream>?
    var writeStream: Unmanaged<CFWriteStream>?
    CFStreamCreatePairWithSocketToHost(nil, host, UInt32(port), &readStream, &writeStream)
    guard let read = readStream, let write = writeStream else {
        throw RemoteDebuggingIOError.streamOpenError
    }
    guard CFReadStreamOpen(read.takeUnretainedValue()) && CFWriteStreamOpen(write.takeUnretainedValue()) else {
        throw RemoteDebuggingIOError.streamOpenError
    }
    return (RemoteDebuggingSocketReader(readStream: read), RemoteDebuggingSocketWriter(writeStream: write))
}

// Parse the host and port that LLDB passes.
private func parseHostAndPort(_ hostAndPort: String) -> (String, Int)? {
    guard let colonIndex = hostAndPort.range(of: ":", options: [.backwards]) else {
        return nil
    }
    let host = hostAndPort.substring(to: colonIndex.lowerBound)
    guard let port = Int(hostAndPort.substring(from: colonIndex.upperBound)) else {
        return nil
    }
    return (host, port)
}
