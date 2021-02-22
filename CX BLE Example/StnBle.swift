//
//  StnBle.swift
//  CX BLE Example
//
//  Created by Robby Madruga on 2/2/21.
//

import Foundation
import CoreBluetooth
import SwiftCoroutine



let UART_SERVICE_UUID = CBUUID(string: "FFF0")
let UART_CHAR_RX_UUID = CBUUID(string: "FFF1")
let UART_CHAR_TX_UUID = CBUUID(string: "FFF2")
let UART_CHAR_LIST = [UART_CHAR_RX_UUID, UART_CHAR_TX_UUID]



class BleManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var centralManager: CBCentralManager!
    
    static var disableScanScope: CoScope = CoScope()
    static var detectProtocolScope: CoScope = CoScope()
    
    @Published var connectingStatus: ConnectingStatus = .NotConnected
    @Published var isSwitchedOn = false
    @Published var peripherals = [Peripheral]()
    @Published var isScanning = false {
        didSet {
            if oldValue == false && self.isScanning == true {
                self.startScanning()
                
                BleManager.disableScanScope = CoScope()
                
                DispatchQueue.main.startCoroutine(in: BleManager.disableScanScope) {
                    try Coroutine.delay(.seconds(60))
                    self.isScanning = false
                }
            }
            
            if oldValue == true && isScanning == false {
                BleManager.disableScanScope.cancel()
                self.stopScanning()
            }
        }
    }
    private var connectingPeripheral: Peripheral?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.global())
        centralManager.delegate = self
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isSwitchedOn = (central.state == .poweredOn)
        if isSwitchedOn {
            isScanning = true
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        var peripheralName: String!
        
        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            peripheralName = name
        } else {
            peripheralName = "Unknown"
        }
        
        DispatchQueue.main.async {
            if self.peripherals.contains(where: { $0.id == peripheral.identifier }) {
                let currentPeripheral = self.getPeripheralById(peripheral.identifier)
                currentPeripheral.rssi = RSSI.intValue
                self.objectWillChange.send()
            } else {
                peripheral.delegate = self
                let newPeripheral = Peripheral(id: peripheral.identifier, name: peripheralName, rssi: RSSI.intValue, device: peripheral)
                self.peripherals.append(newPeripheral)
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([UART_SERVICE_UUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectingStatus = .NotConnected
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if error == nil {
            if let services = peripheral.services {
                for service in services {
                    if service.uuid == UART_SERVICE_UUID {
                        peripheral.discoverCharacteristics(UART_CHAR_LIST, for: service)
                        return
                    }
                }
            }
        } else {
            connectingStatus = .NotConnected
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristics = service.characteristics {
            if UART_CHAR_LIST.allSatisfy({ characteristics.map(\.uuid).contains($0) }) {
                let currentPeripheral = getPeripheralById(peripheral.identifier)
                
                currentPeripheral.rxChar = characteristics.first(where: { $0.uuid == UART_CHAR_RX_UUID })
                currentPeripheral.txChar = characteristics.first(where: { $0.uuid == UART_CHAR_TX_UUID })
                
                peripheral.setNotifyValue(true, for: currentPeripheral.rxChar!)
                
                DispatchQueue.main.async {
                    self.isScanning = false
                    self.connectingStatus = .Detecting
                }
                
                BleManager.detectProtocolScope = CoScope()
                
                DispatchQueue.global().startCoroutine(in: BleManager.detectProtocolScope) {
                    currentPeripheral.scope = BleManager.detectProtocolScope
                    _ = try currentPeripheral.sendCommand("???").await()
                    _ = try currentPeripheral.flush(timeout: .seconds(1)).await()
                    _ = try currentPeripheral.sendCommandWithResponse("ATD").await()
                    _ = try currentPeripheral.sendCommandWithResponse("ATSP 00").await()
                    _ = try currentPeripheral.sendCommandWithResponse("ATH 0").await()
                    _ = try currentPeripheral.sendCommandWithResponse("ATS 0").await()
                    _ = try currentPeripheral.sendCommandWithResponse("0100", timeout: .seconds(10)).await()
                    
                    DispatchQueue.main.async {
                        self.connectingStatus = .Connected
                        currentPeripheral.isConnected = true
                    }
                }
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let currentPeripheral = getPeripheralById(peripheral.identifier)
        if characteristic == currentPeripheral.rxChar {
            currentPeripheral.readChannel.offer(characteristic.value!)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let currentPeripheral = getPeripheralById(peripheral.identifier)
        if characteristic == currentPeripheral.txChar {
            currentPeripheral.writePromise?.complete(with: (error == nil) ? .success(()) : .failure(error!))
        }
    }
    
    func startScanning() {
        centralManager.scanForPeripherals(withServices: [UART_SERVICE_UUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    
    func stopScanning() {
        centralManager.stopScan()
    }
    
    func getPeripheralById(_ id: UUID) -> Peripheral {
        peripherals.first(where: { $0.id == id })!
    }
    
    func connectToPeripheral(id: UUID) {
        let peripheral = getPeripheralById(id)
        connectingPeripheral = peripheral
        connectingStatus = .Connecting
        centralManager.connect(peripheral.device)
    }
    
    func cancelConnection() {
        BleManager.detectProtocolScope.cancel()
        
        let device = getPeripheralById(connectingPeripheral!.id).device
        centralManager.cancelPeripheralConnection(device)
        
        connectingStatus = .NotConnected
        
        isScanning = true
    }
}



extension String {
    func dataChunked(by length: Int) -> [Data] {
        var startIndex = self.startIndex
        var results = [Substring]()
        
        while startIndex < self.endIndex {
            let endIndex = self.index(startIndex, offsetBy: length, limitedBy: self.endIndex) ?? self.endIndex
            results.append(self[startIndex..<endIndex])
            startIndex = endIndex
        }
        
        return results.map { $0.data(using: .ascii)! }
    }
}



class Peripheral: Identifiable, ReaderWriter {
    let id: UUID
    
    var scope: CoScope = CoScope()
    
    let name: String
    let device: CBPeripheral
    
    var rssi: Int
    @Published var isConnected: Bool = false
    
    var rxChar: CBCharacteristic?
    var txChar: CBCharacteristic?
    
    init(id: UUID, name: String, rssi: Int, device: CBPeripheral) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.device = device
    }
    
    var readBuffer = String()
    
    var readChannel = CoChannel<Data>()
    
    var writePromise: CoPromise<()>?
    
    func readChar() -> CoFuture<Character> {
        DispatchQueue.global().coroutineFuture() {
            while let data = self.readChannel.poll() {
                self.readBuffer.append(String(data: data, encoding: .ascii)!)
            }
            
            if self.readBuffer.isEmpty {
                let data = try self.readChannel.awaitReceive()
                self.readBuffer.append(String(data: data, encoding: .ascii)!)
            }
            
            return self.readBuffer.remove(at: self.readBuffer.startIndex)
        }
    }
    
    func writeString(data: String) -> CoFuture<()> {
        DispatchQueue.global().coroutineFuture() {
            for chunk in data.dataChunked(by: self.device.maximumWriteValueLength(for: .withResponse)) {
                self.writePromise = CoPromise<()>()
                self.device.writeValue(chunk, for: self.txChar!, type: .withResponse)
                try self.writePromise?.await(timeout: .seconds(5))
            }
        }.added(to: scope)
    }
    
    func flush(timeout: DispatchTimeInterval) -> CoFuture<()> {
        DispatchQueue.global().coroutineFuture() {
            try Coroutine.delay(timeout)
            while let _ = self.readChannel.poll() {}
            self.readBuffer = String()
        }.added(to: scope)
    }
}
