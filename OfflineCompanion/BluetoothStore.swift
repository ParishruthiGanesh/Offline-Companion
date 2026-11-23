import Foundation
import Combine
import CoreLocation
import CryptoKit
import Security
@preconcurrency import CoreBluetooth

private struct BluetoothPair: Codable {
    var key: Data
    var host: Bool
    var name: String
    var peerName: String
    var enabled: Bool
    var sharing: Bool
    var protocolVersion: Int? = nil
    var accepted: Bool? = nil
    var requestID: UUID? = nil
    var lastLocation: SharedLocationPacket? = nil
    var lastReceivedAt: Date? = nil
    var previousLocation: SharedLocationPacket? = nil
    var previousReceivedAt: Date? = nil
}

private enum PairKeychain {
    private static let service = "com.parishruthi.OfflineCompanion.bluetoothPair.v1"
    static func load() -> Data? {
        var query: [String: Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,
                                    kSecAttrAccount as String:"paired-phone",kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary,&result)
        query.removeAll()
        return status == errSecSuccess ? result as? Data : nil
    }
    static func save(_ data: Data) -> Bool {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"paired-phone"]
        let update = [kSecValueData as String:data]
        let result = SecItemUpdate(query as CFDictionary,update as CFDictionary)
        if result == errSecSuccess { return true }
        guard result == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary,nil) == errSecSuccess
    }
    static func delete() {
        SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"paired-phone"] as CFDictionary)
    }
}

// Core Bluetooth managers and all observable mutations use the MAIN queue.
// Background work is event driven: location callbacks and Bluetooth delegate events, not a timer.
final class BluetoothStore: NSObject, ObservableObject {
    @Published private(set) var paired = false
    @Published private(set) var active = false
    @Published private(set) var connected = false
    @Published private(set) var sharing = false
    @Published private(set) var peerName = "Paired phone"
    @Published private(set) var status = "Experimental background Bluetooth sharing. Pair in person using a private QR link."
    @Published private(set) var pairingURL: URL?
    @Published private(set) var incomingName: String?
    @Published private(set) var awaitingApproval = false
    var localName: String { UserDefaults.standard.string(forKey: "bluetoothDisplayName") ?? "My phone" }
    private var incomingRequestID: UUID?
    private var pendingControl: Message?
    private var invitationRetry: Timer?
    private var outgoingKind: String?
    @Published private(set) var connectionStep = "Open People on both phones."

    private func startInvitationRetry() {
        invitationRetry?.invalidate()
        invitationRetry = Timer.scheduledTimer(withTimeInterval:3,repeats:true) { [weak self] _ in
            guard let self, self.active, !self.connected else { return }
            if self.record?.host == false, let remote = self.remote, remote.state == .connected,
               self.characteristic?.isNotifying == true {
                self.hello()
            } else if self.record?.host == true, self.record?.accepted == true,
                      self.approvedCentral != nil, let requestID = self.record?.requestID {
                self.send(Message(id:UUID(),kind:"accept",name:self.localName,location:nil,requestID:requestID))
            }
        }
    }

    private func stopInvitationRetry() { invitationRetry?.invalidate(); invitationRetry = nil }
    @Published private(set) var received: SharedLocationPacket?
    @Published private(set) var receivedAt: Date?
    @Published private(set) var previousReceived: SharedLocationPacket?
    @Published private(set) var previousReceivedAt: Date?
    @Published private(set) var recentReceipts: [Date] = []
    @Published private(set) var lastSentAt: Date?
    var onSharingChange: ((Bool) -> Void)?
    private var record: BluetoothPair?
    private var central: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var remote: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var localCharacteristic: CBMutableCharacteristic?
    private var approvedCentral: CBCentral?
    private var latestFix: CLLocation?
    private var lastSentFixDate: Date?
    private var queue: [Data] = []
    private var writing = false
    private var addingService = false
    private let valueUUID = CBUUID(string:"F2233717-5C61-4B2A-99C0-84392B05803E")
    private var assembling: [UInt32: Assembly] = [:]
    private var seen = Set<UUID>()
    private struct Assembly { let date: Date; let total: Int; var pieces: [Int:Data] }
    private struct Message: Codable {
        let id: UUID
        let kind: String
        let name: String
        let location: SharedLocationPacket?
        var requestID: UUID? = nil
    }

    override init() {
        super.init()
        if let data = PairKeychain.load(), let saved = try? JSONDecoder().decode(BluetoothPair.self,from:data), saved.key.count == 32, saved.protocolVersion == 2 {
            record = saved
            paired = saved.accepted == true; active = saved.enabled; sharing = paired && saved.enabled && saved.sharing; peerName = saved.peerName
            awaitingApproval = !saved.host && !paired
            received = saved.lastLocation; receivedAt = saved.lastReceivedAt
            previousReceived = saved.previousLocation; previousReceivedAt = saved.previousReceivedAt
            updatePairingURL()
            configureManagers()
            startInvitationRetry()
            status = paired ? "Reconnecting to your person…" : saved.host ? "Show your QR or scan the other phone’s QR." : "Waiting for the other phone to accept…"
        }
    }

    private var serviceUUID: CBUUID? {
        guard let key = record?.key else { return nil }
        let bytes = Array(SHA256.hash(data:key).prefix(16))
        let uuid = UUID(uuid:(bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
        return CBUUID(string:uuid.uuidString)
    }

    private func persist() {
        guard let record, let data = try? JSONEncoder().encode(record) else { return }
        if !PairKeychain.save(data) { status = "Could not save pairing in Keychain. Pairing may not survive a restart." }
    }

    private func updatePairingURL() {
        guard let record, record.host else { pairingURL = nil; return }
        var url = URLComponents(); url.scheme = "offlinecompanion"; url.host = "pair"
        url.queryItems = [URLQueryItem(name:"v",value:"2"),URLQueryItem(name:"key",value:record.key.base64EncodedString()),URLQueryItem(name:"name",value:record.name)]
        pairingURL = url.url
    }

    func updateDisplayName(_ name: String) {
        let clean = String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(20))
        guard !clean.isEmpty else { return }
        UserDefaults.standard.set(clean,forKey:"bluetoothDisplayName")
        if record != nil { record?.name = clean; persist(); updatePairingURL() }
    }

    func prepareInvitation(name: String) {
        let clean = String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(20))
        guard !clean.isEmpty else { return }
        UserDefaults.standard.set(clean,forKey:"bluetoothDisplayName")
        record?.name = clean
        if record != nil { persist(); updatePairingURL(); return }
        var bytes = [UInt8](repeating:0,count:32)
        guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes) == errSecSuccess else { status = "Could not create your QR. Try again."; return }
        record = BluetoothPair(key:Data(bytes),host:true,name:clean,peerName:"Your person",enabled:true,sharing:false,
                               protocolVersion:2,accepted:false)
        active = true; paired = false; sharing = false; awaitingApproval = false
        connectionStep = "Preparing your Bluetooth invitation…"
        persist(); updatePairingURL(); configureManagers()
        status = "Show your QR or scan the other phone’s QR."
    }

    func receivePairingLink(_ url: URL) {
        guard url.scheme == "offlinecompanion", url.host == "pair" else { return }
        guard let components = URLComponents(url:url,resolvingAgainstBaseURL:false),
              components.queryItems?.first(where:{$0.name == "v"})?.value == "2",
              let text = components.queryItems?.first(where:{$0.name == "key"})?.value,
              let key = Data(base64Encoded:text), key.count == 32 else {
            status = "That QR is from an older build or is invalid. Update both phones and scan the new QR."; return
        }
        if record?.key == key {
            if record?.host == true { status = "Scan the QR on the OTHER phone." }
            else { start(); status = paired ? "Reconnecting to your person…" : "Waiting for the other phone to accept…" }
            return
        }
        guard !paired else { status = "You already have a paired person. Disconnect them before pairing someone else."; return }
        let ownName = localName
        let hostName = String((components.queryItems?.first(where:{$0.name == "name"})?.value ?? "Other phone").prefix(20))
        forget()
        record = BluetoothPair(key:key,host:false,name:ownName,peerName:hostName,enabled:true,sharing:false,
                               protocolVersion:2,accepted:false,requestID:UUID())
        peerName = hostName; active = true; awaitingApproval = true
        connectionStep = "Looking for " + hostName + " over Bluetooth…"
        startInvitationRetry()
        persist(); configureManagers()
        status = "Sending invitation to " + hostName + ". They need to tap Accept."
    }

    func acceptInvitation() {
        guard record?.host == true, let requestID = incomingRequestID, let name = incomingName else { return }
        record?.accepted = true; record?.requestID = requestID; record?.peerName = name
        peerName = name; paired = true; incomingName = nil; incomingRequestID = nil
        persist()
        connectionStep = "Sending acceptance to " + name + "…"
        startInvitationRetry()
        send(Message(id:UUID(),kind:"accept",name:localName,location:nil,requestID:requestID))
        status = "Accepted. Finishing connection to " + name + "…"
    }

    func declineInvitation() {
        guard let requestID = incomingRequestID else { return }
        send(Message(id:UUID(),kind:"reject",name:localName,location:nil,requestID:requestID))
        incomingName = nil; incomingRequestID = nil
        status = "Invitation declined."
    }

    func start() {
        guard record != nil else { return }
        if !connected { startInvitationRetry() }
        active = true; record?.enabled = true; persist()
        if central == nil && peripheralManager == nil { configureManagers() }
        begin()
    }

    func stop() {
        active = false
        stopInvitationRetry()
        outgoingKind = nil
        setSharing(false)
        record?.enabled = false; persist()
        central?.stopScan()
        if let remote { central?.cancelPeripheralConnection(remote) }
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        localCharacteristic = nil; addingService = false
        approvedCentral = nil; connected = false; queue = []; writing = false; pendingControl = nil
        status = "Bluetooth sharing stopped. Pairing is still remembered."
    }

    func forget() {
        stop()
        peripheralManager?.removeAllServices()
        central?.delegate = nil; peripheralManager?.delegate = nil; remote?.delegate = nil
        central = nil; peripheralManager = nil; remote = nil; characteristic = nil; localCharacteristic = nil
        record = nil; pairingURL = nil; paired = false; peerName = "Paired phone"
        incomingName = nil; incomingRequestID = nil; awaitingApproval = false; pendingControl = nil
        PairKeychain.delete()
        received = nil; receivedAt = nil; previousReceived = nil; previousReceivedAt = nil; recentReceipts = []; latestFix = nil; assembling = [:]; seen = []
        connectionStep = "Not paired."
        status = "Pairing forgotten on this phone. The other phone should forget it too before pairing again."
    }

    func setSharing(_ value: Bool) {
        guard !value || (paired && active && record?.accepted == true) else { return }
        sharing = value; record?.sharing = value; persist()
        if !value && connected { queue = [] }
        onSharingChange?(value)
        if value {
            status = "Sharing enabled. Fresh locations send when GPS and Bluetooth are available; background timing is controlled by iOS."
            offerLocation(latestFix)
        } else { status = "Your Bluetooth location sharing is off." }
    }

    func offerLocation(_ fix: CLLocation?) {
        latestFix = fix
        guard paired, record?.accepted == true, sharing, active, connected, queue.isEmpty, !writing, let fix,
              fix.horizontalAccuracy >= 0, abs(Date().timeIntervalSince(fix.timestamp)) < 60,
              fix.timestamp != lastSentFixDate,
              Date().timeIntervalSince(lastSentAt ?? .distantPast) >= 10 else { return }
        let packet = SharedLocationPacket(version:1,id:UUID(),latitude:fix.coordinate.latitude,longitude:fix.coordinate.longitude,
                                              accuracy:fix.horizontalAccuracy,recordedAt:fix.timestamp,sentAt:Date())
        send(Message(id:UUID(),kind:"location",name:record?.name ?? "Paired phone",location:packet))
        lastSentAt = Date(); lastSentFixDate = fix.timestamp
    }

    private func configureManagers() {
        guard let record else { return }
        if record.host {
            peripheralManager = CBPeripheralManager(delegate:self,queue:.main,options:[CBPeripheralManagerOptionRestoreIdentifierKey:"offlinecompanion.ble.host.v2." + (serviceUUID?.uuidString ?? "none")])
        } else {
            central = CBCentralManager(delegate:self,queue:.main,options:[CBCentralManagerOptionRestoreIdentifierKey:"offlinecompanion.ble.guest.v2." + (serviceUUID?.uuidString ?? "none")])
        }
    }

    private func begin() {
        guard active, let serviceUUID else { return }
        if let central, central.state == .poweredOn {
            if let remote, remote.state == .connected { discover(remote) }
            else if let remote { central.connect(remote,options:nil) }
            else { central.scanForPeripherals(withServices:[serviceUUID],options:nil) }
        }
        if let manager = peripheralManager, manager.state == .poweredOn {
            if localCharacteristic == nil && !addingService {
                addingService = true
                let value = CBMutableCharacteristic(type:valueUUID,properties:[.write,.notify],value:nil,permissions:[.writeable])
                localCharacteristic = value
                let service = CBMutableService(type:serviceUUID,primary:true); service.characteristics = [value]
                manager.add(service)
            } else if !addingService && !manager.isAdvertising {
                manager.startAdvertising([CBAdvertisementDataServiceUUIDsKey:[serviceUUID]])
            }
            if approvedCentral == nil { approvedCentral = localCharacteristic?.subscribedCentrals?.first }
            if approvedCentral != nil && !connected && queue.isEmpty { hello() }
        }
    }

    private func discover(_ peripheral: CBPeripheral) {
        guard let serviceUUID else { return }
        peripheral.delegate = self
        peripheral.discoverServices([serviceUUID])
    }

    private func hello() {
        let kind = record?.host == true ? "hello" : paired ? "ack" : "request"
        send(Message(id:UUID(),kind:kind,name:record?.name ?? localName,location:nil,requestID:record?.requestID))
    }

    private func flushControl() {
        guard queue.isEmpty, !writing, let message = pendingControl else { return }
        pendingControl = nil; send(message)
    }

    private func send(_ message: Message) {
        guard active, let key = record?.key,
              let raw = try? JSONEncoder().encode(message),
              let data = try? AES.GCM.seal(raw,using:SymmetricKey(data:key)).combined else { return }
        let maximum = record?.host == true ? (approvedCentral?.maximumUpdateValueLength ?? 0) : (remote?.maximumWriteValueLength(for:.withResponse) ?? 0)
        guard maximum > 7 else { return }
        let length = min(180,maximum) - 7
        let total = (data.count + length - 1) / length
        guard total > 0 && total <= 64 else { return }
        guard queue.isEmpty && !writing else {
            if message.kind != "location" { pendingControl = message }
            return
        }
        outgoingKind = message.kind
        if message.kind == "request" { connectionStep = "Sending invitation to " + peerName + "…" }
        let id = UInt32.random(in:0...UInt32.max)
        for index in 0..<total {
            var frame = Data([1,UInt8((id>>24)&255),UInt8((id>>16)&255),UInt8((id>>8)&255),UInt8(id&255),UInt8(index),UInt8(total)])
            frame.append(data.subdata(in:(index*length)..<min(data.count,(index+1)*length)))
            queue.append(frame)
        }
        drain()
    }

    private func drain() {
        guard active else { queue = []; return }
        if record?.host == true, let manager = peripheralManager, let value = localCharacteristic, let central = approvedCentral {
            while let frame = queue.first {
                guard manager.updateValue(frame,for:value,onSubscribedCentrals:[central]) else { return }
                queue.removeFirst()
            }
            outgoingKind = nil
            flushControl()
        } else if !writing, let peripheral = remote, peripheral.state == .connected, let value = characteristic, let frame = queue.first {
            writing = true
            peripheral.writeValue(frame,for:value,type:.withResponse)
        }
    }

    private func acceptFrame(_ frame: Data) {
        let bytes = Array(frame)
        guard active, bytes.count > 7, bytes[0] == 1 else { return }
        let id = UInt32(bytes[1])<<24 | UInt32(bytes[2])<<16 | UInt32(bytes[3])<<8 | UInt32(bytes[4])
        let index = Int(bytes[5]), total = Int(bytes[6])
        guard total > 0 && total <= 64 && index < total else { return }
        assembling = assembling.filter { Date().timeIntervalSince($0.value.date) < 20 }
        if assembling[id] == nil { guard assembling.count < 8 else { return }; assembling[id] = Assembly(date:Date(),total:total,pieces:[:]) }
        guard assembling[id]?.total == total else { assembling[id] = nil; return }
        assembling[id]?.pieces[index] = Data(bytes.dropFirst(7))
        guard let assembly = assembling[id], assembly.pieces.count == total else { return }
        assembling[id] = nil
        var cipher = Data()
        for part in 0..<total { guard let fragment = assembly.pieces[part] else { return }; cipher.append(fragment) }
        guard cipher.count <= 8192, let key = record?.key,
              let box = try? AES.GCM.SealedBox(combined:cipher),
              let raw = try? AES.GCM.open(box,using:SymmetricKey(data:key)),
              let message = try? JSONDecoder().decode(Message.self,from:raw), !seen.contains(message.id) else {
            connectionStep = "Bluetooth data did not match this QR. Cancel the invitation and scan the current QR again."
            return
        }
        if seen.count >= 512 { seen.removeAll() }; seen.insert(message.id)
        let name = String(message.name.prefix(20))
        if message.kind == "request", record?.host == true, let requestID = message.requestID {
            if record?.accepted == true {
                if record?.requestID == requestID {
                    send(Message(id:UUID(),kind:"accept",name:localName,location:nil,requestID:requestID))
                } else {
                    send(Message(id:UUID(),kind:"reject",name:localName,location:nil,requestID:requestID))
                }
            } else {
                incomingName = name; incomingRequestID = requestID
                connectionStep = "Invitation received from " + name + ". Tap Accept invitation."
                status = name + " wants to connect. Tap Accept."
            }
            return
        }
        if message.kind == "accept", record?.host == false,
           let requestID = message.requestID, requestID == record?.requestID {
            record?.accepted = true; paired = true; connected = true; awaitingApproval = false
            stopInvitationRetry(); connectionStep = "Accepted by " + name + ". Connected."
            peerName = name; record?.peerName = name; persist()
            send(Message(id:UUID(),kind:"ack",name:localName,location:nil,requestID:requestID))
            status = "Connected to " + name + ". Turn on Share my location when ready."
            offerLocation(latestFix); return
        }
        if message.kind == "ack", record?.host == true, record?.accepted == true,
           let requestID = message.requestID, requestID == record?.requestID {
            paired = true; connected = true; peerName = name; record?.peerName = name; persist()
            stopInvitationRetry(); connectionStep = "Connection confirmed by " + name + "."
            status = "Connected to " + name + ". Turn on Share my location when ready."
            offerLocation(latestFix); return
        }
        if message.kind == "hello", record?.host == false {
            if paired, record?.accepted == true, let requestID = message.requestID, requestID == record?.requestID {
                connected = true
                stopInvitationRetry(); connectionStep = "Reconnected to " + peerName + "."
                status = "Connected to " + peerName + "."
            }
            hello(); offerLocation(latestFix); return
        }
        if message.kind == "reject", record?.host == false, !paired,
           let requestID = message.requestID, requestID == record?.requestID {
            forget(); prepareInvitation(name:localName)
            status = "Invitation declined. You can scan again."; return
        }
        // No location is accepted or sent before explicit approval and acknowledgement.
        guard paired, connected, record?.accepted == true else { return }
        if message.kind == "location", let packet = message.location, packet.valid {
            let arrival = Date()
            previousReceived = received; previousReceivedAt = receivedAt
            received = packet; receivedAt = arrival
            record?.previousLocation = previousReceived; record?.previousReceivedAt = previousReceivedAt
            record?.lastLocation = packet; record?.lastReceivedAt = arrival
            persist()
            recentReceipts = Array(([arrival] + recentReceipts).prefix(10))
            status = "Bluetooth location received. Check GPS time and received time separately."
        }
    }
}

extension BluetoothStore: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard self.central === central else { return }
        if central.state == .poweredOn { begin() }
        else { connected = false; connectionStep = "Bluetooth is off or permission is unavailable. Check Settings."; status = "Bluetooth unavailable or permission denied. Check iPhone Settings." }
    }
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String:Any]) {
        guard self.central === central else { return }
        if let devices = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral], let restored = devices.first {
            remote = restored; restored.delegate = self
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String:Any], rssi RSSI:NSNumber) {
        guard self.central === central, active, remote == nil || remote?.identifier == peripheral.identifier else { return }
        connectionStep = "Found " + peerName + ". Opening Bluetooth link…"
        remote = peripheral; central.stopScan(); central.connect(peripheral,options:nil)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard self.central === central, active else { return }
        remote = peripheral; characteristic = nil; writing = false; queue = []
        connectionStep = "Bluetooth link open. Checking invitation service…"
        status = "Bluetooth link connected; verifying pairing key…"; discover(peripheral)
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error:Error?) {
        guard self.central === central, remote?.identifier == peripheral.identifier else { return }
        connected = false
        if active { status = "Waiting for the paired phone to return to Bluetooth range."; central.connect(peripheral,options:nil) }
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error:Error?) {
        guard self.central === central, remote?.identifier == peripheral.identifier else { return }
        connected = false; characteristic = nil; writing = false; queue = []; assembling = [:]
        if active { startInvitationRetry(); status = "Bluetooth link lost; reconnecting when the paired phone returns."; central.connect(peripheral,options:nil) }
    }
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard active, peripheral.identifier == remote?.identifier,
              invalidatedServices.contains(where: { $0.uuid == serviceUUID }) else { return }
        connected = false; characteristic = nil; queue = []; writing = false
        central?.cancelPeripheralConnection(peripheral)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error:Error?) {
        guard active, peripheral.identifier == remote?.identifier else { return }
        guard error == nil, let service = peripheral.services?.first(where:{$0.uuid == serviceUUID}) else {
            connectionStep = "Invitation service unavailable. Searching again…"
            remote = nil; characteristic = nil; central?.cancelPeripheralConnection(peripheral)
            if let serviceUUID { central?.scanForPeripherals(withServices:[serviceUUID],options:nil) }
            return
        }
        connectionStep = "Found invitation service. Opening invitation channel…"
        peripheral.discoverCharacteristics([valueUUID],for:service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service:CBService, error:Error?) {
        guard active, peripheral.identifier == remote?.identifier else { return }
        if error == nil, let value = service.characteristics?.first(where:{$0.uuid == valueUUID}) {
            characteristic = value
            connectionStep = "Enabling invitation replies…"
            if value.isNotifying { hello() } else { peripheral.setNotifyValue(true,for:value) }
        } else {
            connectionStep = "Invitation channel unavailable. Reconnecting…"
            central?.cancelPeripheralConnection(peripheral)
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic:CBCharacteristic, error:Error?) {
        guard active, peripheral.identifier == remote?.identifier, characteristic.uuid == valueUUID else { return }
        guard error == nil, characteristic.isNotifying else {
            connectionStep = "Could not enable invitation replies. Reconnecting…"
            central?.cancelPeripheralConnection(peripheral); return
        }
        startInvitationRetry(); hello()
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic:CBCharacteristic, error:Error?) {
        guard peripheral.identifier == remote?.identifier, characteristic.uuid == valueUUID, error == nil, let value = characteristic.value else { return }
        acceptFrame(value)
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic:CBCharacteristic, error:Error?) {
        guard peripheral.identifier == remote?.identifier else { return }
        writing = false
        if !queue.isEmpty { queue.removeFirst() }
        if error != nil {
            queue = []; outgoingKind = nil
            connectionStep = "Invitation write failed; retrying automatically…"
            status = "Bluetooth write failed. Retrying the invitation or waiting for a fresh location."
        } else {
            if queue.isEmpty {
                if outgoingKind == "request", !paired {
                    connectionStep = "Invitation delivered over Bluetooth. Waiting for " + peerName + " to tap Accept."
                }
                outgoingKind = nil
            }
            drain(); flushControl(); if queue.isEmpty { offerLocation(latestFix) }
        }
    }
}

extension BluetoothStore: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral:CBPeripheralManager) {
        guard peripheralManager === peripheral else { return }
        if peripheral.state == .poweredOn { begin() }
        else { connected = false; localCharacteristic = nil; addingService = false; connectionStep = "Bluetooth is off or permission is unavailable. Check Settings."; status = "Bluetooth unavailable or permission denied. Check Settings." }
    }
    func peripheralManager(_ peripheral:CBPeripheralManager, willRestoreState dict:[String:Any]) {
        guard peripheralManager === peripheral else { return }
        if let services = dict[CBPeripheralManagerRestoredStateServicesKey] as? [CBMutableService],
           let service = services.first(where:{$0.uuid == serviceUUID}) {
            localCharacteristic = service.characteristics?.first(where:{$0.uuid == valueUUID}) as? CBMutableCharacteristic
        } else {
            peripheral.removeAllServices(); localCharacteristic = nil; addingService = false
        }
    }
    func peripheralManager(_ peripheral:CBPeripheralManager, didAdd service:CBService, error:Error?) {
        guard peripheralManager === peripheral else { return }
        addingService = false
        if error == nil { begin() } else { localCharacteristic = nil; status = "Could not start the Bluetooth service. Stop and restart Bluetooth." }
    }
    func peripheralManagerDidStartAdvertising(_ peripheral:CBPeripheralManager, error:Error?) {
        guard peripheralManager === peripheral else { return }
        if error != nil { connectionStep = "Bluetooth advertising failed. Check Bluetooth permission."; status = "Bluetooth advertising could not start. Check permissions and retry." }
        else if !paired && incomingName == nil { connectionStep = "Ready. The other phone can scan this QR." }
    }
    func peripheralManager(_ peripheral:CBPeripheralManager, central:CBCentral, didSubscribeTo characteristic:CBCharacteristic) {
        guard peripheralManager === peripheral, active, characteristic.uuid == valueUUID, approvedCentral == nil || approvedCentral?.identifier == central.identifier else { return }
        approvedCentral = central
        connectionStep = "Other phone connected. Waiting for its invitation…"
        status = "Bluetooth link connected; verifying pairing key…"; hello()
    }
    func peripheralManager(_ peripheral:CBPeripheralManager, central:CBCentral, didUnsubscribeFrom characteristic:CBCharacteristic) {
        guard peripheralManager === peripheral, approvedCentral?.identifier == central.identifier else { return }
        approvedCentral = nil; connected = false; queue = []; assembling = [:]
        if !paired { incomingName = nil; incomingRequestID = nil }
        if paired { startInvitationRetry() }
        status = "Bluetooth link lost. Waiting for the paired phone to reconnect."; begin()
    }
    func peripheralManagerIsReady(toUpdateSubscribers peripheral:CBPeripheralManager) { if peripheralManager === peripheral { drain() } }
    func peripheralManager(_ peripheral:CBPeripheralManager, didReceiveWrite requests:[CBATTRequest]) {
        guard let first = requests.first else { return }
        guard peripheralManager === peripheral, active else { peripheral.respond(to:first,withResult:.insufficientAuthorization); return }
        if approvedCentral == nil,
           localCharacteristic?.subscribedCentrals?.contains(where:{$0.identifier == first.central.identifier}) == true {
            approvedCentral = first.central
        }
        guard requests.allSatisfy({$0.characteristic.uuid == valueUUID && $0.offset == 0 && $0.central.identifier == approvedCentral?.identifier}) else {
            peripheral.respond(to:first,withResult:.insufficientAuthorization); return
        }
        for request in requests { if let data = request.value { acceptFrame(data) } }
        peripheral.respond(to:first,withResult:.success)
    }
}

@MainActor
final class BluetoothCoordinator: ObservableObject {
    let transport = BluetoothStore()
    let location = LocationStore(background:true)
    private var subscription: AnyCancellable?
    init() {
        transport.onSharingChange = { [weak location = self.location] value in if value { location?.start() } }
        subscription = location.$fix.sink { [weak transport = self.transport] fix in transport?.offerLocation(fix) }
        if transport.sharing { location.start() }
    }
}
