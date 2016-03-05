//
//  SelfdeTests.swift
//  SelfdeTests
//

import XCTest
@testable import Selfde

class SelfdeTests: XCTestCase {

    func testController() {
        // Main thread info.
        let mainThread: Thread
        do {
            mainThread = try getCurrentThread()
        } catch {
            XCTFail()
            return
        }
        // Initial stop reason.
        do {
            let exception = Exception.stopOnDebuggerAttachmentExceptionForThread(mainThread)
            XCTAssertEqual(exception.reason, "software")
            XCTAssertEqual(exception.signalNumber, 0x11)
        }

        // Used to signal the main thread that the breakpoint is installed.
        let semaphore = dispatch_semaphore_create(0)

        runSelfdeController ({ controller in
            // Allocate an executable memory region.
            let executableMemory: COpaquePointer
            do {
                executableMemory = try controller.allocate(1024, permissions: [.Read, .Write, .Execute])
            } catch {
                XCTFail()
                return
            }
            defer {
                do {
                    try controller.deallocate(executableMemory)
                } catch {
                    XCTFail()
                }
            }

            // Install a breakpoint in that memory.
            do {
                let bp0 = try controller.installBreakpoint(executableMemory)
                let bp1 = try controller.installBreakpoint(executableMemory)
                XCTAssertEqual(bp0.address, bp1.address)
                try controller.removeBreakpoint(bp0)
            } catch {
                XCTFail()
                return
            }

            do {
                let address = try mainThread.getDispatchQueueAddress()
                XCTAssertNotNil(address)
            } catch {
                XCTFail()
            }

            do {
                let count = try mainThread.getSuspendCount()
                XCTAssertEqual(count, 0)
            } catch {
                XCTFail()
            }

            // Resume the main thread.
            dispatch_semaphore_signal(semaphore)

            do {
                let count = try mainThread.getSuspendCount()
                XCTAssertEqual(count, 0)
            } catch {
                XCTFail()
            }

            // Suspend the thread and jump to the executable region with the breakpoint.
            let previousIP: COpaquePointer
            do {
                let state = try mainThread.getRunState()
                XCTAssertEqual(state, RunState.Running)
                try mainThread.suspend()
                var count = try mainThread.getSuspendCount()
                XCTAssertEqual(count, 1)
                previousIP = try mainThread.getInstructionPointer()
                try mainThread.setInstructionPointer(executableMemory)
                try mainThread.resume()
                let exception = try controller.waitForException()
                XCTAssert(exception.thread == mainThread)
                let hitIP = try exception.thread.getInstructionPointer()
                XCTAssertEqual(hitIP, executableMemory)
                XCTAssert(exception.isBreakpoint)
                XCTAssertEqual(exception.reason, "breakpoint")
                XCTAssertEqual(exception.data.count, 2)
                try mainThread.setInstructionPointer(previousIP)
                count = try mainThread.getSuspendCount()
                XCTAssertEqual(count, 1)
                var registerStorage = [UInt8](count: getRegisterContextSize(), repeatedValue: 0)
                let registerContext = try mainThread.getRegisterContext(&registerStorage)
                XCTAssertEqual(registerContext.count, registerStorage.count)
                try mainThread.setRegisterContext(registerContext)
                try mainThread.resume()
            } catch {
                XCTFail()
                return
            }
        }, errorCallback: { error in
            XCTFail()
        })
        dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
        // Long running loop so that the controller can suspend the main thread.
        var j = 0xDead1007
        var f = 2.0
        for i in 0..<1000000 {
            j ^= i
            if (i % 100) == 0{
                f += 0.5
            }
        }
        XCTAssertEqual(j, 3735883783)
        XCTAssertEqual(f, 5002.0)
    }

    func testRemoteDebuggingProtocol() {
        XCTAssertEqual(UnicodeScalar("0").hexValue, 0)
        XCTAssertEqual(UnicodeScalar("a").hexValue, 10)
        XCTAssertEqual(UnicodeScalar("F").hexValue, 15)
        XCTAssertEqual(UnicodeScalar("8").hexValue, 8)

        XCTAssertEqual([UInt8(1), 0xaa, 3].hexString, "01aa03")
        XCTAssertEqual([UInt8(0xFF), 0xAb, 0xe, 0, 0xd].hexString, "ffab0e000d")

        func parsePacket(s: String) -> RemoteDebuggingPacket {
            let bytes = s.utf8.map { UInt8($0) }
            var partialData = [UInt8]()
            let result = parsePackets(&partialData, newData: bytes[0..<bytes.count])
            XCTAssert(partialData.isEmpty)
            XCTAssertEqual(result.count, 1)
            return result[0]
        }

        XCTAssertEqual(parsePacket("$QStartNoAckMode#b0"), RemoteDebuggingPacket.Payload("QStartNoAckMode"))
        XCTAssertEqual(parsePacket("$qSupported:xmlRegisters=i386,arm,mips#12"), RemoteDebuggingPacket.Payload("qSupported:xmlRegisters=i386,arm,mips"))
        XCTAssertEqual(parsePacket("$qHostInfo#9b"), RemoteDebuggingPacket.Payload("qHostInfo"))
        XCTAssertEqual(parsePacket("$qHostInfo#9B"), RemoteDebuggingPacket.Payload("qHostInfo"))
        XCTAssertEqual(parsePacket("$qHostInfo#00"), RemoteDebuggingPacket.InvalidChecksum)
        XCTAssertEqual(parsePacket("$qHostInfo#--"), RemoteDebuggingPacket.InvalidPacket)
        XCTAssertEqual(parsePacket("+"), RemoteDebuggingPacket.ACK)
        XCTAssertEqual(parsePacket("-"), RemoteDebuggingPacket.NACK)
        XCTAssertEqual(parsePacket("$ha#ha"), RemoteDebuggingPacket.InvalidPacket)
        XCTAssertEqual(parsePacket("$vAttach;d20c#2f"), RemoteDebuggingPacket.Payload("vAttach;d20c"))
    }

    func testRemoteDebuggingPacketExtraction() {
        func toString(packet: ArraySlice<UInt8>) -> String {
            var result = ""
            for byte in packet {
                UnicodeScalar(byte).writeTo(&result)
            }
            return result
        }
        do {
            var partialData = [UInt8]()
            let data = [UInt8]("+- $#00$test#00+".utf8)
            let packets = parsePackets(&partialData, newData: data[0..<data.count], checkChecksums: false)
            XCTAssert(partialData.isEmpty)
            XCTAssertEqual(packets.count, 5)
            XCTAssertEqual(packets[0], RemoteDebuggingPacket.ACK)
            XCTAssertEqual(packets[1], RemoteDebuggingPacket.NACK)
            XCTAssertEqual(packets[2], RemoteDebuggingPacket.Payload(""))
            XCTAssertEqual(packets[3], RemoteDebuggingPacket.Payload("test"))
            XCTAssertEqual(packets[4], RemoteDebuggingPacket.ACK)
        }
        do {
            var partialData = [UInt8]()
            var data = [UInt8]("+$ab#20 $test#33 $".utf8)
            var packets = parsePackets(&partialData, newData: data[0..<data.count], checkChecksums: false)
            XCTAssertEqual(toString(partialData[0..<partialData.count]), "$")
            XCTAssertEqual(packets.count, 3)
            XCTAssertEqual(packets[0], RemoteDebuggingPacket.ACK)
            XCTAssertEqual(packets[1], RemoteDebuggingPacket.Payload("ab"))
            XCTAssertEqual(packets[2], RemoteDebuggingPacket.Payload("test"))

            data = [UInt8]("hello#50$test".utf8)
            packets = parsePackets(&partialData, newData: data[0..<data.count], checkChecksums: false)
            XCTAssertEqual(toString(partialData[0..<partialData.count]), "$test")
            XCTAssertEqual(packets.count, 1)
            XCTAssertEqual(packets[0], RemoteDebuggingPacket.Payload("hello"))

            data = [UInt8]("#cc$yes#1".utf8)
            packets = parsePackets(&partialData, newData: data[0..<data.count], checkChecksums: false)
            XCTAssertEqual(toString(partialData[0..<partialData.count]), "$yes#1")
            XCTAssertEqual(packets.count, 1)
            XCTAssertEqual(packets[0], RemoteDebuggingPacket.Payload("test"))

            data = [UInt8]("2+$4#06".utf8)
            packets = parsePackets(&partialData, newData: data[0..<data.count], checkChecksums: false)
            XCTAssert(partialData.isEmpty)
            XCTAssertEqual(packets.count, 3)
            XCTAssertEqual(packets[0], RemoteDebuggingPacket.Payload("yes"))
            XCTAssertEqual(packets[1], RemoteDebuggingPacket.ACK)
            XCTAssertEqual(packets[2], RemoteDebuggingPacket.Payload("4"))
        }
    }

    func testRemoteDebuggingProtocolBinaryEncoding() {
        do {
            let data = Array("Hello #$*wor}ld".utf8)
            let encodedData = data.encodedBinaryData
            XCTAssertEqual(data.count + 4, encodedData.count)
            XCTAssertEqual(encodedData, [72, 101, 108, 108, 111, 32, 125, 3, 125, 4, 125, 10, 119, 111, 114, 125, 93, 108, 100])
            let decodedData = encodedData.decodedBinaryData
            XCTAssertEqual(data, decodedData)
        }
        do {
            let data = Array("Test 2".utf8) + [0xff, 0xfe, 0xcc]
            let encodedData = data.encodedBinaryData
            XCTAssertEqual(data, encodedData)
            let decodedData = encodedData.decodedBinaryData
            XCTAssertEqual(data, decodedData)
        }
    }

    func testDebuggingUtils() {
        let threads = [ThreadID(2), ThreadID(400)]
        let primaryThread = threads[0]

        do {
            let entries = [ThreadResumeEntry(thread: .ID(2), action: .Continue, address: nil)]
            let result = extractResumeActionsForThreads(threads, primaryThread: primaryThread, entries: entries, defaultAction: .None)
            XCTAssertEqual(result.count, 2)
            XCTAssertEqual(result[0].0, 2)
            XCTAssertEqual(result[0].1, ThreadResumeAction.Continue)
            XCTAssertEqual(result[0].2, nil)
            XCTAssertEqual(result[1].0, 400)
            XCTAssertEqual(result[1].1, ThreadResumeAction.None)
            XCTAssertEqual(result[1].2, nil)
        }
        do {
            let entries = [ThreadResumeEntry(thread: .All, action: .Continue, address: nil)]
            let result = extractResumeActionsForThreads(threads, primaryThread: primaryThread, entries: entries, defaultAction: .None)
            XCTAssertEqual(result.count, 2)
            XCTAssertEqual(result[0].0, 2)
            XCTAssertEqual(result[0].1, ThreadResumeAction.Continue)
            XCTAssertEqual(result[0].2, nil)
            XCTAssertEqual(result[1].0, 400)
            XCTAssertEqual(result[1].1, ThreadResumeAction.Continue)
            XCTAssertEqual(result[1].2, nil)
        }
        do {
            let entries = [ThreadResumeEntry(thread: .ID(2), action: .Continue, address: nil), ThreadResumeEntry(thread: .ID(400), action: .Step, address: nil)]
            let result = extractResumeActionsForThreads(threads, primaryThread: primaryThread, entries: entries, defaultAction: .Stop)
            XCTAssertEqual(result.count, 2)
            XCTAssertEqual(result[0].0, 2)
            XCTAssertEqual(result[0].1, ThreadResumeAction.Continue)
            XCTAssertEqual(result[0].2, nil)
            XCTAssertEqual(result[1].0, 400)
            XCTAssertEqual(result[1].1, ThreadResumeAction.Step)
            XCTAssertEqual(result[1].2, nil)
        }
        do {
            let entries = [ThreadResumeEntry(thread: .Any, action: .Stop, address: COpaquePointer(bitPattern: 0x20)), ThreadResumeEntry(thread: .ID(400), action: .Step, address: nil)]
            let result = extractResumeActionsForThreads(threads, primaryThread: primaryThread, entries: entries, defaultAction: .Stop)
            XCTAssertEqual(result.count, 2)
            XCTAssertEqual(result[0].0, 2)
            XCTAssertEqual(result[0].1, ThreadResumeAction.Stop)
            XCTAssertEqual(result[0].2, COpaquePointer(bitPattern: 0x20))
            XCTAssertEqual(result[1].0, 400)
            XCTAssertEqual(result[1].1, ThreadResumeAction.Step)
            XCTAssertEqual(result[1].2, nil)
        }
    }

    func testRemoteDebuggingPacketHandling() {
        enum MockError: ErrorType { case NotExpected }

        class MockConnection: RemoteDebuggingConnection {
            func read() throws -> ArraySlice<UInt8> {
                return []
            }
            func write(data: ArraySlice<UInt8>) throws {
            }
            func close() {
            }
        }

        class MockDebugger: Debugger {
            var expectedSetBreakpoints: [(UInt, Int)] = []
            var removeBreakpoint: [UInt] = []
            var expectedAllocates: [(Int, MemoryPermissions)]
            var expectedDeallocates: [COpaquePointer]
            var expectedMemoryReads: [(UInt, Int)]
            var expectedMemoryWrites:[(UInt, [UInt8])]
            var expectedRegisterReads: [(ThreadID, UInt32, UInt32, UInt64)]
            var expectedRegisterWrites: [(ThreadID, UInt32, UInt32, UInt64)]
            var expectedRegisterContextReads: [(ThreadID, [UInt8])]
            var expectedRegisterContextWrites: [(ThreadID, [UInt8])]
            
            init(expectedSetBreakpoints: [(UInt, Int)] = [], expectedAllocates: [(Int, MemoryPermissions)] = [], expectedDeallocates: [COpaquePointer] = [], expectedMemoryReads: [(UInt, Int)] = [], expectedMemoryWrites: [(UInt, [UInt8])] = [], expectedRegisterReads: [(ThreadID, UInt32, UInt32, UInt64)] = [], expectedRegisterWrites: [(ThreadID, UInt32, UInt32, UInt64)] = [], expectedRegisterContextReads: [(ThreadID, [UInt8])] = [], expectedRegisterContextWrites: [(ThreadID, [UInt8])] = []) {
                self.expectedSetBreakpoints = expectedSetBreakpoints
                self.expectedAllocates = expectedAllocates
                self.expectedDeallocates = expectedDeallocates
                self.expectedMemoryReads = expectedMemoryReads
                self.expectedMemoryWrites = expectedMemoryWrites
                self.expectedRegisterReads = expectedRegisterReads
                self.expectedRegisterWrites = expectedRegisterWrites
                self.expectedRegisterContextReads = expectedRegisterContextReads
                self.expectedRegisterContextWrites = expectedRegisterContextWrites
            }

            var primaryThreadID: ThreadID {
                return 12
            }

            var threads: [ThreadID] {
                return [primaryThreadID]
            }

            func attach(processID: Int) throws {
                XCTAssertEqual(processID, 0x12345)
            }

            func getStopInfoForThread(threadID: ThreadID) throws -> ThreadStopInfo {
                XCTFail()
                return ThreadStopInfo(signalNumber: 0, dispatchQueueAddress: nil, machInfo: nil)
            }

            func isThreadAlive(threadID: ThreadID) throws -> Bool {
                return threadID == 0x405
            }

            func setBreakpoint(address: COpaquePointer, byteSize: Int) throws {
                guard let bp = expectedSetBreakpoints.first else {
                    throw MockError.NotExpected
                }
                XCTAssertEqual(COpaquePointer(bitPattern: bp.0), address)
                XCTAssertEqual(bp.1, byteSize)
                expectedSetBreakpoints.removeFirst()
            }
            
            func removeBreakpoint(address: COpaquePointer) throws {
                
            }

            func getSharedLibraryInfoAddress() throws -> COpaquePointer {
                return COpaquePointer(bitPattern: 0x1013)
            }

            func allocate(size: Int, permissions: MemoryPermissions) throws -> COpaquePointer {
                guard let value = expectedAllocates.first else {
                    throw MockError.NotExpected
                }
                XCTAssertEqual(value.0, size)
                XCTAssertEqual(value.1, permissions)
                expectedAllocates.removeFirst()
                return COpaquePointer(bitPattern: 0xADBEEF)
            }
            
            func deallocate(address: COpaquePointer) throws {
                guard let value = expectedDeallocates.first else {
                    throw MockError.NotExpected
                }
                expectedDeallocates.removeFirst()
                XCTAssertEqual(value, address)
            }
            
            let bytes: UnsafeMutablePointer<UInt8> = {
                let result = UnsafeMutablePointer<UInt8>.alloc(256)
                result.initializeFrom((0..<256).map { UInt8($0) })
                return result
            }()
            
            func readMemory(address: COpaquePointer, size: Int) throws -> MemoryReadResult {
                guard let value = expectedMemoryReads.first else {
                    throw MockError.NotExpected
                }
                expectedMemoryReads.removeFirst()
                XCTAssertEqual(COpaquePointer(bitPattern: value.0), address)
                XCTAssertEqual(value.1, size)
                return MemoryReadResult.Bytes(UnsafeBufferPointer<UInt8>(start: UnsafePointer<UInt8>(bytes), count: size))
            }
            
            func writeMemory(address: COpaquePointer, bytes: [UInt8]) throws {
                guard let value = expectedMemoryWrites.first else {
                    throw MockError.NotExpected
                }
                expectedMemoryWrites.removeFirst()
                XCTAssertEqual(COpaquePointer(bitPattern: value.0), address)
                XCTAssertEqual(value.1.count, bytes.count)
                XCTAssert(zip(value.1, bytes).reduce(true) { $0 ? $1.0 == $1.1 : false })
            }

            func getIPRegisterValueForThread(threadID: ThreadID) throws -> COpaquePointer {
                return COpaquePointer(bitPattern: 0xdeadbeef)
            }

            #if arch(x86_64)
            func getRegisterValueForThread(threadID: ThreadID, registerID: UInt32, registerSetID: UInt32, inout dest: [UInt8]) throws -> ArraySlice<UInt8> {
                guard let value = expectedRegisterReads.first else {
                    throw MockError.NotExpected
                }
                expectedRegisterReads.removeFirst()
                precondition(dest.count >= 8)
                XCTAssertEqual(value.0, threadID)
                XCTAssertEqual(value.1, registerID)
                XCTAssertEqual(value.2, registerSetID)
                dest.withUnsafeMutableBufferPointer { (inout ptr: UnsafeMutableBufferPointer<UInt8>) in
                    UnsafeMutablePointer<UInt64>(ptr.baseAddress).memory = value.3
                }
                return dest.prefix(8)
            }

            func setRegisterValueForThread(threadID: ThreadID, registerID: UInt32, registerSetID: UInt32, source: ArraySlice<UInt8>) throws {
                guard let value = expectedRegisterWrites.first else {
                    throw MockError.NotExpected
                }
                expectedRegisterWrites.removeFirst()
                precondition(source.count >= 8)
                XCTAssertEqual(value.0, threadID)
                XCTAssertEqual(value.1, registerID)
                XCTAssertEqual(value.2, registerSetID)
                let val = source.withUnsafeBufferPointer {
                    UnsafePointer<UInt64>($0.baseAddress).memory
                }
                XCTAssertEqual(value.3, val)
            }
            #endif

            var registerContextSize: Int {
                return sizeof(UInt64) * 3
            }
        
            func getRegisterContextForThread(threadID: ThreadID, inout dest: [UInt8]) throws -> ArraySlice<UInt8> {
                guard let value = expectedRegisterContextReads.first else {
                    throw MockError.NotExpected
                }
                expectedRegisterContextReads.removeFirst()
                XCTAssertEqual(value.0, threadID)
                for (i, byte) in value.1.enumerate() {
                    dest[i] = byte
                }
                return dest.prefix(value.1.count)
            }
        
            func setRegisterContextForThread(threadID: ThreadID, source: ArraySlice<UInt8>) throws {
                guard let value = expectedRegisterContextWrites.first else {
                    throw MockError.NotExpected
                }
                expectedRegisterContextWrites.removeFirst()
                XCTAssertEqual(value.0, threadID)
                XCTAssertEqual(value.1.count, source.count)
                XCTAssert(zip(value.1, source).reduce(true) { $0 ? $1.0 == $1.1 : false })
            }
        }

        func registerContext(registers: [UInt64]) -> [UInt8] {
            var result = [UInt8](count: registers.count * sizeof(UInt64), repeatedValue: 0)
            registers.withUnsafeBufferPointer { ptr in
                for (i, byte) in UnsafeMutableBufferPointer(start: UnsafeMutablePointer<UInt8>(ptr.baseAddress), count: result.count).enumerate() {
                    result[i] = byte
                }
            }
            return result
        }

        let server = DebugServer(debugger: MockDebugger(expectedSetBreakpoints: [(0xABA, 1), (0xBAA, 255)], expectedAllocates: [(0x104, [MemoryPermissions.Read, MemoryPermissions.Write]), (0x1234567812345678, [MemoryPermissions.Read, MemoryPermissions.Write, MemoryPermissions.Execute])], expectedDeallocates: [COpaquePointer(bitPattern: 0xadbeef)], expectedMemoryReads: [(0xA0B, 4), (0x123456789, 0x11)], expectedMemoryWrites: [(0xBeef, [0,7,0xAA,0xBB,0xCC,0xEE,0x12,0x34])], expectedRegisterReads: [(0xc, 0, 1, 0), (0xa2a, 0, 1, 2), (0xa2a, 0x10, 1, 0x4091), (0, 0xf, 1, UInt64.max)], expectedRegisterWrites: [(0x808, 0, 1, 0xefcdab78563412), (0x808, 0xa, 1, 0x1000000000000000), (0x71f, 3, 1, UInt64.max), (0x808, 0x11, 1, 2)], expectedRegisterContextReads: [(0x42, registerContext([2, UInt64.max, 0x4091]))], expectedRegisterContextWrites: [(0x42, registerContext([0xF1Fa, UInt64(Int64.max), 0]))]),
            connection: MockConnection()
        )

        XCTAssertEqual(server.handlePacketPayload("foo"), ResponseResult.Unimplemented)
        XCTAssertEqual(server.handlePacketPayload(""), ResponseResult.Unimplemented)
        XCTAssertEqual("\(ErrorResultKind.E08)", "E08")

        // Breakpoints
        XCTAssertEqual(server.handlePacketPayload("Z0,ABA,1"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("z0,ABA,1"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("Z0,BAA,FF"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("z0,BAA,2"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("z1,BA,0"), ResponseResult.Unimplemented)
        XCTAssertEqual(server.handlePacketPayload("z2,F00,0"), ResponseResult.Unimplemented)
        XCTAssert(server.handlePacketPayload("z0").isInvalid)
        XCTAssert(server.handlePacketPayload("z0,").isInvalid)
        XCTAssert(server.handlePacketPayload("z0,A").isInvalid)
        XCTAssert(server.handlePacketPayload("z0,A,").isInvalid)

        // Memory allocate/deallocate
        XCTAssertEqual(server.handlePacketPayload("_M104,rw"), ResponseResult.Response("adbeef"))
        XCTAssertEqual(server.handlePacketPayload("_madBEef"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("_M1234567812345678,rwx"), ResponseResult.Response("adbeef"))
        XCTAssert(server.handlePacketPayload("_M1234567812345678A,rw").isInvalid)
        XCTAssert(server.handlePacketPayload("_M,").isInvalid)

        // Memory read/write
        XCTAssertEqual(server.handlePacketPayload("mA0B,4"), ResponseResult.Response("00010203"))
        XCTAssertEqual(server.handlePacketPayload("m123456789,011"), ResponseResult.Response("000102030405060708090a0b0c0d0e0f10"))
        XCTAssert(server.handlePacketPayload("mA0B,-").isInvalid)
        XCTAssert(server.handlePacketPayload("mA").isInvalid)
        XCTAssert(server.handlePacketPayload("m").isInvalid)
        
        XCTAssertEqual(server.handlePacketPayload("MBEEF,8:0007AABBCCEE1234"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("M0,0"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("MBEEF,16:0000AABBCCEE1234"), ResponseResult.Error(.E09))
        XCTAssert(server.handlePacketPayload("M").isInvalid)
        XCTAssert(server.handlePacketPayload("Ma,").isInvalid)
        XCTAssert(server.handlePacketPayload("M10,4").isInvalid)
        XCTAssert(server.handlePacketPayload("M10,4:a").isInvalid)

        // Register info
        XCTAssertEqual(server.handlePacketPayload("qRegisterInfo1000"), ResponseResult.Error(.E45))
        XCTAssert(server.handlePacketPayload("qRegisterInfo").isInvalid)
        #if arch(x86_64)
            XCTAssertEqual(server.handlePacketPayload("qRegisterInfo0"), ResponseResult.Response("name:rax;bitsize:64;offset:0;encoding:uint;format:hex;set:General Purpose Registers;ehframe:0;dwarf:0;invalidate-regs:0,15,25,35,39;"))
        #endif

        // Register read/write
        XCTAssertEqual(server.handlePacketPayload("p0"), ResponseResult.Response("0000000000000000"))
        XCTAssertEqual(server.handlePacketPayload("QThreadSuffixSupported"), ResponseResult.OK)
        XCTAssert(server.handlePacketPayload("p").isInvalid)
        XCTAssertEqual(server.handlePacketPayload("pffffff;thread:0;"), ResponseResult.Error(.E47))
        XCTAssert(server.handlePacketPayload("P").isInvalid)
        XCTAssertEqual(server.handlePacketPayload("Pffffff=0000000000000010"), ResponseResult.Error(.E47))
        XCTAssert(server.handlePacketPayload("P0,00").isInvalid)
        XCTAssert(server.handlePacketPayload("P0=123;thread:0;").isInvalid)
        XCTAssert(server.handlePacketPayload("P0=12;thread:0;").isInvalid)
        #if arch(x86_64)
            XCTAssertEqual(server.handlePacketPayload("p0;thread:a2a;"), ResponseResult.Response("0200000000000000"))
            XCTAssertEqual(server.handlePacketPayload("p10;thread:a2a;"), ResponseResult.Response("9140000000000000"))
            XCTAssertEqual(server.handlePacketPayload("pF;thread:0;"), ResponseResult.Response("ffffffffffffffff"))
            XCTAssertEqual(server.handlePacketPayload("P0=12345678abcdef00;thread:808;"), ResponseResult.OK)
            XCTAssertEqual(server.handlePacketPayload("Pa=0000000000000010;thread:808;"), ResponseResult.OK)
            XCTAssertEqual(server.handlePacketPayload("P3=ffffffffffffffff;thread:71f;"), ResponseResult.OK)
            XCTAssertEqual(server.handlePacketPayload("P11=0200000000000000;thread:808;"), ResponseResult.OK)
        #endif
        XCTAssert(server.handlePacketPayload("g").isInvalid)
        XCTAssertEqual(server.handlePacketPayload("g;thread:42;"), ResponseResult.Response("0200000000000000ffffffffffffffff9140000000000000"))
        XCTAssert(server.handlePacketPayload("G").isInvalid)
        XCTAssert(server.handlePacketPayload("G;thread:0;").isInvalid)
        XCTAssert(server.handlePacketPayload("G=12;thread:0;").isInvalid)
        XCTAssertEqual(server.handlePacketPayload("GFaF1000000000000ffffffffffffff7f0000000000000000;thread:42;"), ResponseResult.OK)

        // Thread commands
        XCTAssertEqual(server.handlePacketPayload("qC"), ResponseResult.Response("QCc"))
        XCTAssertEqual(server.handlePacketPayload("Hg0"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("qC"), ResponseResult.Response("QCc"))
        XCTAssertEqual(server.handlePacketPayload("Hg30"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("qC"), ResponseResult.Response("QC30"))
        XCTAssertEqual(server.handlePacketPayload("Hg0"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("qC"), ResponseResult.Response("QCc"))
        XCTAssertEqual(server.handlePacketPayload("Hg40"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("qC"), ResponseResult.Response("QC40"))
        XCTAssertEqual(server.handlePacketPayload("Hg-1"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("qC"), ResponseResult.Response("QCc"))
        XCTAssertEqual(server.handlePacketPayload("Hc40"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("Hc0"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("Hc-1"), ResponseResult.OK)
        XCTAssert(server.handlePacketPayload("Ha").isInvalid)
        XCTAssert(server.handlePacketPayload("Hc-").isInvalid)
        XCTAssert(server.handlePacketPayload("Hc-2").isInvalid)
        XCTAssertEqual(server.handlePacketPayload("T20"), ResponseResult.Error(.E16))
        XCTAssertEqual(server.handlePacketPayload("T405"), ResponseResult.OK)
        XCTAssert(server.handlePacketPayload("T").isInvalid)

        // Continue/step
        XCTAssertEqual(server.handlePacketPayload("c"), ResponseResult.Resume(actions: [ThreadResumeEntry(thread: .All, action: .Continue, address: nil)], defaultAction: .Continue))
        XCTAssertEqual(server.handlePacketPayload("c0"), ResponseResult.Resume(actions: [ThreadResumeEntry(thread: .All, action: .Continue, address: COpaquePointer(bitPattern: 0))], defaultAction: .Continue))
        XCTAssertEqual(server.handlePacketPayload("c4000"), ResponseResult.Resume(actions: [ThreadResumeEntry(thread: .All, action: .Continue, address: COpaquePointer(bitPattern: 0x4000))], defaultAction: .Continue))
        XCTAssertEqual(server.handlePacketPayload("Hc40"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("c"), ResponseResult.Resume(actions: [ThreadResumeEntry(thread: .ID(0x40), action: .Continue, address: nil)], defaultAction: .Continue))
        XCTAssert(server.handlePacketPayload("c=").isInvalid)
        XCTAssertEqual(server.handlePacketPayload("s"), ResponseResult.Resume(actions: [ThreadResumeEntry(thread: .ID(0x40), action: .Step, address: nil)], defaultAction: .Stop))
        XCTAssertEqual(server.handlePacketPayload("s123456789ab"), ResponseResult.Resume(actions: [ThreadResumeEntry(thread: .ID(0x40), action: .Step, address: COpaquePointer(bitPattern: 0x123456789ab))], defaultAction: .Stop))
        XCTAssertEqual(server.handlePacketPayload("Hc0"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("s"), ResponseResult.Resume(actions: [ThreadResumeEntry(thread: .ID(0xc), action: .Step, address: nil)], defaultAction: .Stop))
        XCTAssertEqual(server.handlePacketPayload("Hc-1"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("s"), ResponseResult.Resume(actions: [ThreadResumeEntry(thread: .ID(0xC), action: .Step, address: nil)], defaultAction: .Stop))
        // vCont as well..
        XCTAssertEqual(server.handlePacketPayload("vCont;c"), ResponseResult.Resume(actions: [ThreadResumeEntry(thread: .All, action: .Continue, address: nil)], defaultAction: .Continue))
        XCTAssertEqual(server.handlePacketPayload("vCont;s"), ResponseResult.Resume(actions: [ThreadResumeEntry(thread: .ID(0xC), action: .Step, address: nil)], defaultAction: .Stop))
        XCTAssertEqual(server.handlePacketPayload("vCont;c:404"), ResponseResult.Resume(actions: [ThreadResumeEntry(thread: .ID(0x404), action: .Continue, address: nil)], defaultAction: .Stop))
        XCTAssertEqual(server.handlePacketPayload("vCont;s:20"), ResponseResult.Resume(actions: [ThreadResumeEntry(thread: .ID(0x20), action: .Step, address: nil)], defaultAction: .Stop))
        XCTAssertEqual(server.handlePacketPayload("vCont;c;s:20"), ResponseResult.Resume(actions: [ThreadResumeEntry(thread: .ID(0x20), action: .Step, address: nil)], defaultAction: .Continue))
        XCTAssertEqual(server.handlePacketPayload("vCont;s;c:40"), ResponseResult.Resume(actions: [ThreadResumeEntry(thread: .ID(0x40), action: .Continue, address: nil)], defaultAction: .Step))
        XCTAssert(server.handlePacketPayload("vCont").isInvalid)
        XCTAssert(server.handlePacketPayload("vCont;").isInvalid)
        XCTAssert(server.handlePacketPayload("vCont;a").isInvalid)
        XCTAssert(server.handlePacketPayload("vCont;c:").isInvalid)

        // vAttach
        XCTAssertEqual(server.handlePacketPayload("vAttach;12345"), ResponseResult.ThreadStopReply)
        XCTAssert(server.handlePacketPayload("vAttach;").isInvalid)

        // Stop info
        XCTAssertEqual(server.handlePacketPayload("QListThreadsInStopReply"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("qThreadStopInfo12"), ResponseResult.StopReplyForThread(0x12))
        XCTAssertEqual(server.handlePacketPayload("qThreadStopInfo0"), ResponseResult.StopReplyForThread(0))
        XCTAssert(server.handlePacketPayload("qThreadStopInfo").isInvalid)

        // Queries
        XCTAssertEqual(server.handlePacketPayload("qShlibInfoAddr"), ResponseResult.Response("1013"))
        XCTAssertEqual(server.handlePacketPayload("qSymbol::"), ResponseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("qSymbol:64697370617463685f71756575655f6f666673657473"), ResponseResult.OK)
        server.handlePacketPayload("qSupported")
        server.handlePacketPayload("qSupported:xmlRegisters=arm")
        switch server.handlePacketPayload("qHostInfo") {
        case .Response(let response):
            XCTAssertNotNil(response.rangeOfString("cputype:"))
            XCTAssertNotNil(response.rangeOfString("cpusubtype:"))
            XCTAssertNotNil(response.rangeOfString("ostype:"))
            XCTAssertNotNil(response.rangeOfString("endian:"))
            XCTAssertNotNil(response.rangeOfString("ptrsize:"))
            break
        default:
            XCTFail()
        }
        switch server.handlePacketPayload("qProcessInfo") {
        case .Response(let response):
            XCTAssertNotNil(response.rangeOfString("pid:12345"))
            XCTAssertNotNil(response.rangeOfString("cputype:"))
            XCTAssertNotNil(response.rangeOfString("cpusubtype:"))
            XCTAssertNotNil(response.rangeOfString("ostype:"))
            XCTAssertNotNil(response.rangeOfString("endian:"))
            XCTAssertNotNil(response.rangeOfString("ptrsize:"))
            break
        default:
            XCTFail()
        }
        XCTAssertEqual(server.handlePacketPayload("?"), ResponseResult.ThreadStopReply)

        // Kill/detach
        XCTAssertEqual(server.handlePacketPayload("D"), ResponseResult.Exit("OK"))
        XCTAssertEqual(server.handlePacketPayload("k"), ResponseResult.Exit("X09"))

        // Stop replys
        do {
            #if arch(x86_64)
            class StopMockDebugger: MockDebugger {
                var expectedThreadStopInfos: [(ThreadID, ThreadStopInfo)]

                init(expectedThreadStopInfos: [(ThreadID, ThreadStopInfo)]) {
                    self.expectedThreadStopInfos = expectedThreadStopInfos
                    super.init()
                }

                override func getStopInfoForThread(threadID: ThreadID) throws -> ThreadStopInfo {
                    guard let value = expectedThreadStopInfos.first else {
                        throw MockError.NotExpected
                    }
                    expectedThreadStopInfos.removeFirst()
                    XCTAssertEqual(value.0, threadID)
                    return value.1
                }

                override func getRegisterValueForThread(threadID: ThreadID, registerID: UInt32, registerSetID: UInt32, inout dest: [UInt8]) throws -> ArraySlice<UInt8> {
                    dest.withUnsafeMutableBufferPointer { (inout ptr: UnsafeMutableBufferPointer<UInt8>) in
                        UnsafeMutablePointer<UInt64>(ptr.baseAddress).memory = 0x1234567812345678
                    }
                    return dest.prefix(8)
                }
            }
            let server = DebugServer(debugger: StopMockDebugger(expectedThreadStopInfos: [
                (0xc, ThreadStopInfo(signalNumber: 5, dispatchQueueAddress: nil, machInfo: nil)),
                (0x689, ThreadStopInfo(signalNumber: 0x20, dispatchQueueAddress: nil, machInfo: nil)),
                (0xc, ThreadStopInfo(signalNumber: 5, dispatchQueueAddress: COpaquePointer(bitPattern: 0xabc), machInfo: ThreadStopInfo.MachInfo(exceptionType: 0x40, exceptionData: [0x2,0xFFFF]))),
                (0xc, ThreadStopInfo(signalNumber: 0xf0, dispatchQueueAddress: nil, machInfo: nil))
            ]), connection: MockConnection())
            XCTAssertEqual(server.handleStopReply(ResponseResult.ThreadStopReply), ResponseResult.Response("T05thread:c;00:7856341278563412;01:7856341278563412;02:7856341278563412;03:7856341278563412;04:7856341278563412;05:7856341278563412;06:7856341278563412;07:7856341278563412;08:7856341278563412;09:7856341278563412;0a:7856341278563412;0b:7856341278563412;0c:7856341278563412;0d:7856341278563412;0e:7856341278563412;0f:7856341278563412;10:7856341278563412;11:7856341278563412;12:7856341278563412;13:7856341278563412;14:7856341278563412;"))
            XCTAssertEqual(server.handleStopReply(ResponseResult.StopReplyForThread(0x689)), ResponseResult.Response("T20thread:689;00:7856341278563412;01:7856341278563412;02:7856341278563412;03:7856341278563412;04:7856341278563412;05:7856341278563412;06:7856341278563412;07:7856341278563412;08:7856341278563412;09:7856341278563412;0a:7856341278563412;0b:7856341278563412;0c:7856341278563412;0d:7856341278563412;0e:7856341278563412;0f:7856341278563412;10:7856341278563412;11:7856341278563412;12:7856341278563412;13:7856341278563412;14:7856341278563412;"))
            XCTAssertEqual(server.handleStopReply(ResponseResult.ThreadStopReply), ResponseResult.Response("T05thread:c;qaddr:abc;00:7856341278563412;01:7856341278563412;02:7856341278563412;03:7856341278563412;04:7856341278563412;05:7856341278563412;06:7856341278563412;07:7856341278563412;08:7856341278563412;09:7856341278563412;0a:7856341278563412;0b:7856341278563412;0c:7856341278563412;0d:7856341278563412;0e:7856341278563412;0f:7856341278563412;10:7856341278563412;11:7856341278563412;12:7856341278563412;13:7856341278563412;14:7856341278563412;metype:40;mecount:2;medata:2;medata:ffff;"))
            XCTAssertEqual(server.handlePacketPayload("QListThreadsInStopReply"), ResponseResult.OK)
            XCTAssertEqual(server.handleStopReply(ResponseResult.ThreadStopReply), ResponseResult.Response("Tf0thread:c;threads:c;thread-pcs:deadbeef;00:7856341278563412;01:7856341278563412;02:7856341278563412;03:7856341278563412;04:7856341278563412;05:7856341278563412;06:7856341278563412;07:7856341278563412;08:7856341278563412;09:7856341278563412;0a:7856341278563412;0b:7856341278563412;0c:7856341278563412;0d:7856341278563412;0e:7856341278563412;0f:7856341278563412;10:7856341278563412;11:7856341278563412;12:7856341278563412;13:7856341278563412;14:7856341278563412;"))
            #endif
        }
    }
}

extension ThreadReference: Equatable { }

public func == (lhs: ThreadReference, rhs: ThreadReference) -> Bool {
    switch (lhs, rhs) {
    case (.ID(let x), .ID(let y)):
        return x == y
    case (.Any, .Any), (.All, .All):
        return true
    default:
        return false
    }
}

extension ThreadResumeEntry: Equatable { }

public func == (lhs: ThreadResumeEntry, rhs: ThreadResumeEntry) -> Bool {
    return lhs.thread == rhs.thread && lhs.action == rhs.action && lhs.address == rhs.address
}

extension RemoteDebuggingPacket: Equatable { }

func == (lhs: RemoteDebuggingPacket, rhs: RemoteDebuggingPacket) -> Bool {
    switch (lhs, rhs) {
    case (.Payload(let x), .Payload(let y)):
        return x == y
    case (.InvalidChecksum, .InvalidChecksum), (.ACK, .ACK), (.NACK, .NACK), (.InvalidPacket, .InvalidPacket):
        return true
    default:
        return false
    }
}

extension ResponseResult: Equatable { }

func == (lhs: ResponseResult, rhs: ResponseResult) -> Bool {
    switch (lhs, rhs) {
    case (.None, .None), (.OK, .OK), (.Unimplemented, .Unimplemented), (.Invalid, .Invalid), (.Error, .Error), (.Resume, .Resume), (.ThreadStopReply, .ThreadStopReply), (.Exit, .Exit):
        return true
    case (.StopReplyForThread(let x), .StopReplyForThread(let y)):
        return x == y
    case (.Response(let x), .Response(let y)):
        return x == y
    default:
        return false
    }
}

extension ResponseResult {
    var isInvalid: Bool {
        if case .Invalid = self {
            return true
        }
        return false
    }
}

