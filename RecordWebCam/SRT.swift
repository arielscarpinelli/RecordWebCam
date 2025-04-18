import Foundation
import CoreMedia
import HaishinKit
import libsrt

enum SRTError: Error {
    case connection(String)
}

class SRT {
    
    private var socket: SRTSOCKET = SRT_INVALID_SOCK
    private var clientSocket: SRTSOCKET = SRT_INVALID_SOCK
    private var writer: TSWriter = .init()
    
    func initSrt() throws {
        // TODO: audio
        writer.expectedMedias.insert(.video)

        socket = srt_create_socket()
        if socket == SRT_INVALID_SOCK {
            throw SRTError.connection("can't create socket")
        }
        srt_startup()
        
        var addr: sockaddr_in = .init()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16BigToHost(UInt16(9710))
        if inet_pton(AF_INET, "0.0.0.0", &addr.sin_addr) != 1 {
            throw SRTError.connection("can't create sockaddr")
        }
        var addr_cp = addr
        var stat = withUnsafePointer(to: &addr_cp) { ptr -> Int32 in
            let psa = UnsafeRawPointer(ptr).assumingMemoryBound(to: sockaddr.self)
            return srt_bind(socket, psa, Int32(MemoryLayout.size(ofValue: addr)))
        }
        if stat == SRT_ERROR {
            srt_close(socket)
            throw SRTError.connection("can't bind")
        }
        stat = srt_listen(socket, 1)
        if stat == SRT_ERROR {
            srt_close(socket)
            throw SRTError.connection("can't listen")
        }
        accept()
        Task {
            for await data in writer.output {
                self.send(data)
            }
        }
    }
    
    func accept() {
        Task.detached { [self] in
            while !isConnected {
                let accept = srt_accept(socket, nil, nil)
                if accept <= SRT_ERROR {
                    print("unable to accept \(accept)")
                } else {
                    clientSocket = accept
                    print("connected")
                }
            }
        }
    }
    
    public func append(_ sampleBuffer: CMSampleBuffer) {
        writer.videoFormat = sampleBuffer.formatDescription
        writer.append(sampleBuffer)
    }

    
    func close() {
        if isConnected {
            let result = srt_close(clientSocket)
            if result <= SRT_ERROR {
                print("failed to disconnect \(result)")
            } else {
                print("disconnected")
            }
            clientSocket = SRT_INVALID_SOCK
        }
    }

    private func send(_ data:Data) {
        if isConnected {
            for data in data.chunk(1316) {
                let result = data.withUnsafeBytes { pointer in
                    guard let buffer = pointer.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                        return SRT_ERROR
                    }
                    return srt_sendmsg(clientSocket, buffer, Int32(data.count), -1, 0)
                }
                if result <= SRT_ERROR {
                    print("failed to send \(result)")
                    close()
                    accept();
                }
            }
        } else {
            print("not conntected, ignoring frame")
        }
    }
    
    var isConnected: Bool {
        return clientSocket != SRT_INVALID_SOCK
    }

}

// this is copy-pasta from Hainshin as I can't just import the extension
extension Data {
    func chunk(_ size: Int) -> [Data] {
        if count < size {
            return [self]
        }
        var chunks: [Data] = []
        let length = count
        var offset = 0
        repeat {
            let thisChunkSize = ((length - offset) > size) ? size : (length - offset)
            chunks.append(subdata(in: offset..<offset + thisChunkSize))
            offset += thisChunkSize
        } while offset < length
        return chunks
    }
}
