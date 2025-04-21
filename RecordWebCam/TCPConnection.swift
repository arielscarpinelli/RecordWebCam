import Network
import CoreMedia
import Foundation // Needed for Data conversion and dispatchMain

protocol ConnectionDelegate {
    func onDisconnect()
}

// --- Configuration ---
let port: NWEndpoint.Port = 4747

// --- Server Class ---
class TCPConnection {

    var listener: NWListener?
    private var connectionsByID: [Int: ServerConnection] = [:] // Keep track of connections
    private var nextConnectionID: Int = 0
    var delegate: ConnectionDelegate?
    
    var isSendingVideo: Bool {
        get {
            return connectionsByID.values.contains { c in c.sendVideo }
        }
    }

    // Start listening for incoming connections
    func start() throws {
        // Use .tcp parameters. For UDP, use .udp
        // You can configure TLS/security here if needed in parameters.
        let parameters = NWParameters.tcp
        
        // Set allowsLocalNetwork to true to allow local network discovery.
        parameters.includePeerToPeer = true

        self.listener = try NWListener(using: parameters, on: port)
        listener!.stateUpdateHandler = self.handleStateChange(to:)
        listener!.newConnectionHandler = self.handleNewConnection(_:)
        print("Server starting on port \(port)...")
    }

    // Handle listener state changes (ready, failed, etc.)
    private func handleStateChange(to newState: NWListener.State) {
        switch newState {
        case .ready:
            print("Listener ready on port \(listener!.port!)")
        case .failed(let error):
            print("Listener failed with error: \(error.localizedDescription)")
        case .cancelled:
            print("Listener cancelled.")
        default:
            print("Listener state changed: \(newState)")
        }
    }
    
    func accept() {
        listener!.start(queue: .main) // Use the main dispatch queue
        print("Server listener accepting conections")
    }

    // Handle a new incoming connection
    private func handleNewConnection(_ connection: NWConnection) {
        print("New connection received...")
        let serverConnection = ServerConnection(connection: connection, id: nextConnectionID)
        connectionsByID[nextConnectionID] = serverConnection
        nextConnectionID += 1 // Increment ID for the next connection

        // Set a closure to be called when this connection is stopped
        serverConnection.didStopCallback = { [weak self] error in
            print("Connection \(serverConnection.id) stopped.")
            if let error = error {
                print("  Error: \(error.localizedDescription)")
            }
            self?.connectionDidStop(serverConnection)
        }

        serverConnection.start() // Start handling the connection
        print("Accepted connection \(serverConnection.id) from \(connection.endpoint)")
    }

    // Clean up when a connection stops
    private func connectionDidStop(_ connection: ServerConnection) {
        connectionsByID.removeValue(forKey: connection.id)
        print("Removed connection \(connection.id). Total connections: \(connectionsByID.count)")
        delegate?.onDisconnect()
    }

    // Stop the listener
    func close() {
        print("Stopping server...")
        self.listener!.cancel()
        // Close all active connections
        for (_, connection) in connectionsByID {
            connection.stop()
        }
        connectionsByID.removeAll()
    }
    
    public func append(_ sampleBuffer: CMSampleBuffer) {
        do {
            
            let data = try packetize(sampleBuffer)
            
            var packet = Data()
            
            let pts = (UInt64) (CMTimeGetSeconds(sampleBuffer.presentationTimeStamp) * 1000)
            let len: UInt32 = UInt32(data.count)
            
            withUnsafePointer(to: pts.bigEndian) { value in
                packet.append(UnsafeRawPointer(value).assumingMemoryBound(to: UInt8.self), count: MemoryLayout<UInt64>.size)
            }

            withUnsafePointer(to: len.bigEndian) { value in
                packet.append(UnsafeRawPointer(value).assumingMemoryBound(to: UInt8.self), count: MemoryLayout<UInt32>.size)
            }
            
            packet.append(data)
            
            connectionsByID.values.forEach { connection in
                if connection.sendVideo {
                    connection.send(packet)
                }
            }

        } catch {
            print("failed to send \(String(describing: error))")
        }
    }
    
    func packetize(_ sampleBuffer: CMSampleBuffer) throws -> Data {
        var packet = Data()
        
        let data = try sampleBuffer.dataBuffer?.dataBytes()
        
        if data != nil {
            
            var parameterSets = Data()
            let isSync = !sampleBuffer.sampleAttachments.isEmpty && sampleBuffer.sampleAttachments[0][.notSync] == nil
            if isSync {
                sampleBuffer.formatDescription?.parameterSets.forEach {
                    parameterSets.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                    parameterSets.append(contentsOf: $0)
                }
            }
            
            packet.append(parameterSets)
            
            var nalus = data!
            
            while !nalus.isEmpty {
                let naluSize = Data.Index(CFSwapInt32BigToHost(nalus.withUnsafeBytes { $0.baseAddress!.assumingMemoryBound(to: UInt32.self).pointee }))
                
                let naluData = nalus.advanced(by: 4)
                
                packet.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                packet.append(naluData.subdata(in: 0..<naluSize))
                nalus = naluData.advanced(by: naluSize)
            }
        }

        return packet
            
    }

}

// --- Connection Handling Class ---
class ServerConnection {
    let id: Int
    let connection: NWConnection
    var didStopCallback: ((Error?) -> Void)? = nil // Closure to call when stopped
    var sendVideo = false

    init(connection: NWConnection, id: Int) {
        self.connection = connection
        self.id = id
    }

    // Start handling the connection's events
    func start() {
        connection.stateUpdateHandler = self.handleStateChange(to:)
        setupReceive() // Start listening for incoming data
        connection.start(queue: .main) // Use the main queue for simplicity
    }

    // Handle connection state changes
    private func handleStateChange(to state: NWConnection.State) {
        switch state {
        case .ready:
            print("Connection \(id): Ready")
        case .failed(let error):
            print("Connection \(id): Failed with error: \(error.localizedDescription)")
            stop(error: error)
        case .cancelled:
            print("Connection \(id): Cancelled")
            stop(error: nil)
        case .waiting(let error):
            print("Connection \(id): Waiting - \(error.localizedDescription)")
        case .preparing:
            print("Connection \(id): Preparing")
        case .setup:
             print("Connection \(id): Setup")
        @unknown default:
            print("Connection \(id): Unknown state")
        }
    }


    // Setup receiving data (called once initially, then recursively)
    private func setupReceive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] (data, _, isComplete, error) in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                let request = String(data: data, encoding: .ascii)
                if let request = request {
                    print ("incoming: \(request)")
                    if request.contains("video") {
                        sendVideo = true
                    } else if request.contains("HTTP/1.1\r\n\r\n") {
                        send("200 OK\r\n\r\n".data(using: .ascii)!)
                    }
                } else {
                    // wtf??
                }
            }

            if isComplete {
                print("Connection \(self.id): Receive complete (connection closed by peer)")
                self.stop(error: nil) // Connection closed by client
            } else if let error = error {
                print("Connection \(self.id): Receive error: \(error.localizedDescription)")
                self.stop(error: error) // Handle error
            } else {
                // Continue listening for more data
                self.setupReceive()
            }
        }
    }

    // Send a message back to the client
    func send(_ data: Data) {

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                print("Connection \(self.id): Send error: \(error.localizedDescription)")
                self.stop(error: error)
            }
        })
    }

    // Stop the connection
    func stop(error: Error? = nil) {
        connection.stateUpdateHandler = nil // Prevent further state updates
        connection.cancel()
        if let callback = didStopCallback {
             // Run the callback on the main queue asynchronously to avoid potential deadlocks
             DispatchQueue.main.async {
                 callback(error)
             }
            self.didStopCallback = nil // Ensure callback is only called once
        }
    }

}
