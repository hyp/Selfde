//
//  SelfdeTests.swift
//  SelfdeTests
//
//  Created by alex on 21/02/2016.
//  Copyright © 2016 hyp. All rights reserved.
//

import XCTest
@testable import Selfde

class SelfdeTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    private var threadStackAddress: COpaquePointer?

    func threadRun() {
        var stack: Int = 0xDEADBEEF
        withUnsafePointer(&stack) {
            threadStackAddress = COpaquePointer($0)
            print(threadStackAddress)
        }
        var j = 0
        // Run some code for a long time so that the controller can drop a breakpoint into it.
        for i in 0..<1000000000 {
            j = j &+ i
        }
        print("Test thread:", j)
    }

    func testExample() {
       /* do {
            // Helper thread.
            let thread = NSThread(target:self, selector:#selector(self.threadRun), object:nil)
            thread.start()
            try runSelfdeController { controller in
                do {
                
                    try controller.suspendThreads()
                    print("Test threads are suspended")
                    let threads = try controller.getThreads()
                    for thread in threads  {
                        let state = try thread.getRunState()
                        XCTAssertEqual(state, RunState.Waiting)
                        let ip = try thread.getInstructionPointer()
                        let sp = try thread.getStackPointer()
                        print("Thread: \(thread.opaqueValue), runState: \(state), ip = \(ip), sp = \(sp)")
                    }
                    if let last = threads.last {
                        let bp = try controller.installBreakpoint(last.getInstructionPointer())
                        //try controller.removeBreakpoint(bp)
                    }
                    sleep(5)
                    try controller.resumeThreads()
                    print("Test threads are resumed")
                    sleep(5)
                } catch {
                    XCTFail()
                }
            }
        } catch {
            XCTFail()
        }*/
    }
    
    func testRemoteDebuggingProtocol() {
        XCTAssertEqual(UnicodeScalar("0").hexValue, 0)
        XCTAssertEqual(UnicodeScalar("a").hexValue, 10)
        XCTAssertEqual(UnicodeScalar("F").hexValue, 15)
        XCTAssertEqual(UnicodeScalar("8").hexValue, 8)

        XCTAssertEqual([UInt8(1), 0xaa, 3].hexString, "01aa03")
        XCTAssertEqual([UInt8(0xFF), 0xAb, 0xe, 0, 0xd].hexString, "ffab0e000d")

        func parsePacket(s: String) -> PacketPayloadResult {
            let bytes = s.utf8.map { UInt8($0) }
            return parsePacketPayload(bytes[0..<bytes.count])
        }

        XCTAssertEqual(parsePacket(""), PacketPayloadResult.NoPacket)
        XCTAssertEqual(parsePacket("$QStartNoAckMode#b0"), PacketPayloadResult.Payload("QStartNoAckMode"))
        XCTAssertEqual(parsePacket("$qSupported:xmlRegisters=i386,arm,mips#12"), PacketPayloadResult.Payload("qSupported:xmlRegisters=i386,arm,mips"))
        XCTAssertEqual(parsePacket("$qHostInfo#9b"), PacketPayloadResult.Payload("qHostInfo"))
        XCTAssertEqual(parsePacket("$qHostInfo#9B"), PacketPayloadResult.Payload("qHostInfo"))
        XCTAssertEqual(parsePacket("$qHostInfo#00"), PacketPayloadResult.InvalidChecksum)
        XCTAssertEqual(parsePacket("$qHostInfo0"), PacketPayloadResult.InvalidPacket)
        XCTAssertEqual(parsePacket("+"), PacketPayloadResult.ControlPacket)
        XCTAssertEqual(parsePacket("-"), PacketPayloadResult.ControlPacket)
        XCTAssertEqual(parsePacket("ha"), PacketPayloadResult.InvalidPacket)
        XCTAssertEqual(parsePacket("$vAttach;d20c#2f"), PacketPayloadResult.Payload("vAttach;d20c"))
    }

    func testRemoteDebuggingPacketHandling() {
        enum MockError: ErrorType { case NotExpected }
        
        final class MockDebugger: Debugger {
            var expectedResumes: [([ThreadResumeEntry], ThreadResumeAction)]
            var expectedSetBreakpoints: [(UInt, Int)] = []
            var removeBreakpoint: [UInt] = []
            var expectedAllocates: [(Int, MemoryPermissions)]
            var expectedDeallocates: [COpaquePointer]
            var expectedMemoryReads: [(UInt, Int)]
            var expectedMemoryWrites:[(UInt, [UInt8])]
            var expectedRegisterReads: [(UInt, UInt32, UInt32, UInt64)]
            var expectedRegisterWrites: [(UInt, UInt32, UInt32, UInt64)]
            var expectedRegisterContextReads: [(UInt, [UInt8])]
            var expectedRegisterContextWrites: [(UInt, [UInt8])]
            
            init(expectedResumes: [([ThreadResumeEntry], ThreadResumeAction)] = [], expectedSetBreakpoints: [(UInt, Int)] = [], expectedAllocates: [(Int, MemoryPermissions)] = [], expectedDeallocates: [COpaquePointer] = [], expectedMemoryReads: [(UInt, Int)] = [], expectedMemoryWrites: [(UInt, [UInt8])] = [], expectedRegisterReads: [(UInt, UInt32, UInt32, UInt64)] = [], expectedRegisterWrites: [(UInt, UInt32, UInt32, UInt64)] = [], expectedRegisterContextReads: [(UInt, [UInt8])] = [], expectedRegisterContextWrites: [(UInt, [UInt8])] = []) {
                self.expectedResumes = expectedResumes
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

            var primaryThreadID: UInt {
                return 12
            }

            func attach(processID: Int) throws {
                XCTAssertEqual(processID, 0x12345)
            }

            func resume(actions: [ThreadResumeEntry], defaultAction: ThreadResumeAction) throws {
                guard let value = expectedResumes.first else {
                    throw MockError.NotExpected
                }
                expectedResumes.removeFirst()
                XCTAssert(value.0 == actions)
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
            
            func killInferior() throws {
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
            
            #if arch(x86_64)
            func getRegisterValueForThread(threadID: UInt, registerID: UInt32, registerSetID: UInt32, inout dest: [UInt8]) throws -> ArraySlice<UInt8> {
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

            func setRegisterValueForThread(threadID: UInt, registerID: UInt32, registerSetID: UInt32, source: ArraySlice<UInt8>) throws {
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
        
            func getRegisterContextForThread(threadID: UInt, inout dest: [UInt8]) throws -> ArraySlice<UInt8> {
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
        
            func setRegisterContextForThread(threadID: UInt, source: ArraySlice<UInt8>) throws {
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

        let server = DebugServer(debugger: MockDebugger(expectedResumes: [
            ([ThreadResumeEntry(thread: .All, action: .Continue, address: nil)], .Continue),
            ([ThreadResumeEntry(thread: .All, action: .Continue, address: COpaquePointer(bitPattern: 0))], .Continue),
            ([ThreadResumeEntry(thread: .All, action: .Continue, address: COpaquePointer(bitPattern: 0x4000))], .Continue),
            ([ThreadResumeEntry(thread: .ID(0x40), action: .Continue, address: nil)], .Continue),
            ([ThreadResumeEntry(thread: .ID(0x40), action: .Step, address: nil)], .Stop),
            ([ThreadResumeEntry(thread: .ID(0x40), action: .Step, address: COpaquePointer(bitPattern: 0x123456789ab))], .Stop),
            ([ThreadResumeEntry(thread: .ID(0xc), action: .Step, address: nil)], .Stop),
            ([ThreadResumeEntry(thread: .ID(0xC), action: .Step, address: nil)], .Stop),
            ([ThreadResumeEntry(thread: .All, action: .Continue, address: nil)], .Continue),
            ([ThreadResumeEntry(thread: .ID(0xC), action: .Step, address: nil)], .Stop),
            ([ThreadResumeEntry(thread: .ID(0x404), action: .Continue, address: nil)], .Stop),
            ([ThreadResumeEntry(thread: .ID(0x20), action: .Step, address: nil)], .Stop),
            ([ThreadResumeEntry(thread: .ID(0x20), action: .Step, address: nil)], .Continue),
            ([ThreadResumeEntry(thread: .ID(0x40), action: .Continue, address: nil)], .Step),
            ], expectedSetBreakpoints: [(0xABA, 1), (0xBAA, 255)], expectedAllocates: [(0x104, [MemoryPermissions.Read, MemoryPermissions.Write]), (0x1234567812345678, [MemoryPermissions.Read, MemoryPermissions.Write, MemoryPermissions.Execute])], expectedDeallocates: [COpaquePointer(bitPattern: 0xadbeef)], expectedMemoryReads: [(0xA0B, 4), (0x123456789, 0x11)], expectedMemoryWrites: [(0xBeef, [0,7,0xAA,0xBB,0xCC,0xEE,0x12,0x34])], expectedRegisterReads: [(0xc, 0, 1, 0), (0xa2a, 0, 1, 2), (0xa2a, 0x10, 1, 0x4091), (0, 0xf, 1, UInt64.max)], expectedRegisterWrites: [(0x808, 0, 1, 0xefcdab78563412), (0x808, 0xa, 1, 0x1000000000000000), (0x71f, 3, 1, UInt64.max), (0x808, 0x11, 1, 2)], expectedRegisterContextReads: [(0x42, registerContext([2, UInt64.max, 0x4091]))], expectedRegisterContextWrites: [(0x42, registerContext([0xF1Fa, UInt64(Int64.max), 0]))]))

        XCTAssertEqual(server.handlePacketPayload("foo"), ParseResult.Unimplemented)
        XCTAssertEqual(server.handlePacketPayload(""), ParseResult.Unimplemented)
        XCTAssertEqual("\(ErrorResultKind.E08)", "E08")

        // Breakpoints
        XCTAssertEqual(server.handlePacketPayload("Z0,ABA,1"), ParseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("z0,ABA,1"), ParseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("Z0,BAA,FF"), ParseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("z0,BAA,2"), ParseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("z1,BA,0"), ParseResult.Unimplemented)
        XCTAssertEqual(server.handlePacketPayload("z2,F00,0"), ParseResult.Unimplemented)
        XCTAssert(server.handlePacketPayload("z0").isInvalid)
        XCTAssert(server.handlePacketPayload("z0,").isInvalid)
        XCTAssert(server.handlePacketPayload("z0,A").isInvalid)
        XCTAssert(server.handlePacketPayload("z0,A,").isInvalid)

        // Memory allocate/deallocate
        XCTAssertEqual(server.handlePacketPayload("_M104,rw"), ParseResult.Response("adbeef"))
        XCTAssertEqual(server.handlePacketPayload("_madBEef"), ParseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("_M1234567812345678,rwx"), ParseResult.Response("adbeef"))
        XCTAssert(server.handlePacketPayload("_M1234567812345678A,rw").isInvalid)
        XCTAssert(server.handlePacketPayload("_M,").isInvalid)

        // Memory read/write
        XCTAssertEqual(server.handlePacketPayload("mA0B,4"), ParseResult.Response("00010203"))
        XCTAssertEqual(server.handlePacketPayload("m123456789,011"), ParseResult.Response("000102030405060708090a0b0c0d0e0f10"))
        XCTAssert(server.handlePacketPayload("mA0B,-").isInvalid)
        XCTAssert(server.handlePacketPayload("mA").isInvalid)
        XCTAssert(server.handlePacketPayload("m").isInvalid)
        
        XCTAssertEqual(server.handlePacketPayload("MBEEF,8:0007AABBCCEE1234"), ParseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("M0,0"), ParseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("MBEEF,16:0000AABBCCEE1234"), ParseResult.Error(.E09))
        XCTAssert(server.handlePacketPayload("M").isInvalid)
        XCTAssert(server.handlePacketPayload("Ma,").isInvalid)
        XCTAssert(server.handlePacketPayload("M10,4").isInvalid)
        XCTAssert(server.handlePacketPayload("M10,4:a").isInvalid)

        // Register info
        XCTAssertEqual(server.handlePacketPayload("qRegisterInfo1000"), ParseResult.Error(.E45))
        XCTAssert(server.handlePacketPayload("qRegisterInfo").isInvalid)
        #if arch(x86_64)
            XCTAssertEqual(server.handlePacketPayload("qRegisterInfo0"), ParseResult.Response("name:rax;bitsize:64;offset:0;encoding:uint;format:hex;set:General Purpose Registers;ehframe:0;dwarf:0;invalidate-regs:0,15,25,35,39;"))
        #endif

        // Register read/write
        XCTAssertEqual(server.handlePacketPayload("p0"), ParseResult.Response("0000000000000000"))
        XCTAssertEqual(server.handlePacketPayload("QThreadSuffixSupported"), ParseResult.OK)
        XCTAssert(server.handlePacketPayload("p").isInvalid)
        XCTAssertEqual(server.handlePacketPayload("pffffff;thread:0;"), ParseResult.Error(.E47))
        XCTAssert(server.handlePacketPayload("P").isInvalid)
        XCTAssertEqual(server.handlePacketPayload("Pffffff=0000000000000010"), ParseResult.Error(.E47))
        XCTAssert(server.handlePacketPayload("P0,00").isInvalid)
        XCTAssert(server.handlePacketPayload("P0=123;thread:0;").isInvalid)
        XCTAssert(server.handlePacketPayload("P0=12;thread:0;").isInvalid)
        #if arch(x86_64)
            XCTAssertEqual(server.handlePacketPayload("p0;thread:a2a;"), ParseResult.Response("0200000000000000"))
            XCTAssertEqual(server.handlePacketPayload("p10;thread:a2a;"), ParseResult.Response("9140000000000000"))
            XCTAssertEqual(server.handlePacketPayload("pF;thread:0;"), ParseResult.Response("ffffffffffffffff"))
            XCTAssertEqual(server.handlePacketPayload("P0=12345678abcdef00;thread:808;"), ParseResult.OK)
            XCTAssertEqual(server.handlePacketPayload("Pa=0000000000000010;thread:808;"), ParseResult.OK)
            XCTAssertEqual(server.handlePacketPayload("P3=ffffffffffffffff;thread:71f;"), ParseResult.OK)
            XCTAssertEqual(server.handlePacketPayload("P11=0200000000000000;thread:808;"), ParseResult.OK)
        #endif
        XCTAssert(server.handlePacketPayload("g").isInvalid)
        XCTAssertEqual(server.handlePacketPayload("g;thread:42;"), ParseResult.Response("0200000000000000ffffffffffffffff9140000000000000"))
        XCTAssert(server.handlePacketPayload("G").isInvalid)
        XCTAssert(server.handlePacketPayload("G;thread:0;").isInvalid)
        XCTAssert(server.handlePacketPayload("G=12;thread:0;").isInvalid)
        XCTAssertEqual(server.handlePacketPayload("GFaF1000000000000ffffffffffffff7f0000000000000000;thread:42;"), ParseResult.OK)

        // Thread commands
        XCTAssertEqual(server.handlePacketPayload("qC"), ParseResult.Response("QCc"))
        XCTAssertEqual(server.handlePacketPayload("Hg0"), ParseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("qC"), ParseResult.Response("QCc"))
        XCTAssertEqual(server.handlePacketPayload("Hg30"), ParseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("qC"), ParseResult.Response("QC30"))
        XCTAssertEqual(server.handlePacketPayload("Hg0"), ParseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("qC"), ParseResult.Response("QCc"))
        XCTAssertEqual(server.handlePacketPayload("Hg40"), ParseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("qC"), ParseResult.Response("QC40"))
        XCTAssertEqual(server.handlePacketPayload("Hg-1"), ParseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("qC"), ParseResult.Response("QCc"))
        XCTAssertEqual(server.handlePacketPayload("Hc40"), ParseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("Hc0"), ParseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("Hc-1"), ParseResult.OK)
        XCTAssert(server.handlePacketPayload("Ha").isInvalid)
        XCTAssert(server.handlePacketPayload("Hc-").isInvalid)
        XCTAssert(server.handlePacketPayload("Hc-2").isInvalid)

        // Continue/step
        XCTAssertEqual(server.handlePacketPayload("c"), ParseResult.WaitForThreadStopReply)
        XCTAssertEqual(server.handlePacketPayload("c0"), ParseResult.WaitForThreadStopReply)
        XCTAssertEqual(server.handlePacketPayload("c4000"), ParseResult.WaitForThreadStopReply)
        XCTAssertEqual(server.handlePacketPayload("Hc40"), ParseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("c"), ParseResult.WaitForThreadStopReply)
        XCTAssert(server.handlePacketPayload("c=").isInvalid)
        XCTAssertEqual(server.handlePacketPayload("s"), ParseResult.WaitForThreadStopReply)
        XCTAssertEqual(server.handlePacketPayload("s123456789ab"), ParseResult.WaitForThreadStopReply)
        XCTAssertEqual(server.handlePacketPayload("Hc0"), ParseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("s"), ParseResult.WaitForThreadStopReply)
        XCTAssertEqual(server.handlePacketPayload("Hc-1"), ParseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("s"), ParseResult.WaitForThreadStopReply)
        // vCont as well..
        XCTAssertEqual(server.handlePacketPayload("vCont;c"), ParseResult.WaitForThreadStopReply)
        XCTAssertEqual(server.handlePacketPayload("vCont;s"), ParseResult.WaitForThreadStopReply)
        XCTAssertEqual(server.handlePacketPayload("vCont;c:404"), ParseResult.WaitForThreadStopReply)
        XCTAssertEqual(server.handlePacketPayload("vCont;s:20"), ParseResult.WaitForThreadStopReply)
        XCTAssertEqual(server.handlePacketPayload("vCont;c;s:20"), ParseResult.WaitForThreadStopReply)
        XCTAssertEqual(server.handlePacketPayload("vCont;s;c:40"), ParseResult.WaitForThreadStopReply)
        XCTAssert(server.handlePacketPayload("vCont").isInvalid)
        XCTAssert(server.handlePacketPayload("vCont;").isInvalid)
        XCTAssert(server.handlePacketPayload("vCont;a").isInvalid)
        XCTAssert(server.handlePacketPayload("vCont;c:").isInvalid)

        // vAttach
        XCTAssertEqual(server.handlePacketPayload("vAttach;12345"), ParseResult.ThreadStopReply)
        XCTAssert(server.handlePacketPayload("vAttach;").isInvalid)

        // Stop info
        XCTAssertEqual(server.handlePacketPayload("QListThreadsInStopReply"), ParseResult.OK)

        // Queries
        XCTAssertEqual(server.handlePacketPayload("qShlibInfoAddr"), ParseResult.Response("1013"))
        XCTAssertEqual(server.handlePacketPayload("qSymbol::"), ParseResult.OK)
        XCTAssertEqual(server.handlePacketPayload("qSymbol:64697370617463685f71756575655f6f666673657473"), ParseResult.OK)
        server.handlePacketPayload("qSupported")
        server.handlePacketPayload("qSupported:xmlRegisters=arm")
        // TODO: qXfer:features:read
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
    }
}

extension ThreadReference: Equatable { }

func == (lhs: ThreadReference, rhs: ThreadReference) -> Bool {
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

func == (lhs: ThreadResumeEntry, rhs: ThreadResumeEntry) -> Bool {
    return lhs.thread == rhs.thread && lhs.action == rhs.action && lhs.address == rhs.address
}

extension PacketPayloadResult: Equatable { }

func == (lhs: PacketPayloadResult, rhs: PacketPayloadResult) -> Bool {
    switch (lhs, rhs) {
    case (.Payload(let x), .Payload(let y)):
        return x == y
    case (.NoPacket, .NoPacket), (.InvalidChecksum, .InvalidChecksum), (.ControlPacket, .ControlPacket), (.InvalidPacket, .InvalidPacket):
        return true
    default:
        return false
    }
}

extension ParseResult: Equatable { }

func == (lhs: ParseResult, rhs: ParseResult) -> Bool {
    switch (lhs, rhs) {
    case (.NoReply, .NoReply), (.OK, .OK), (.Unimplemented, .Unimplemented), (.Invalid, .Invalid), (.Error, .Error), (.WaitForThreadStopReply, .WaitForThreadStopReply), (.ThreadStopReply, .ThreadStopReply):
        return true
    case (.Response(let x), .Response(let y)):
        return x == y
    default:
        return false
    }
}

extension ParseResult {
    var isInvalid: Bool {
        if case .Invalid = self {
            return true
        }
        return false
    }
}

