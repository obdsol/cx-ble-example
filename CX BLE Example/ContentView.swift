//
//  ContentView.swift
//  CX BLE Example
//
//  Created by Robby Madruga on 2/2/21.
//

import SwiftUI
import SwiftCoroutine


class PidConfig: Identifiable {
    let id: UUID = UUID()
    var ecu: String
    var request: String
    
    init(ecu: String, request: String) {
        self.ecu = ecu
        self.request = request
    }
    
    var data: String = "NO DATA"
}


class PidConfigManager: ObservableObject {
    var commander: Peripheral
    static var scope: CoScope = CoScope()
    
    init(commander: Peripheral) {
        self.commander = commander
    }
    
    @Published var configList: [PidConfig] = [
        PidConfig(ecu: "7E0", request: "010C1"),
        PidConfig(ecu: "7E1", request: "010C1"),
        PidConfig(ecu: "7E2", request: "010D1")
    ]
    
    func addPidConfig(ecu: String, request: String) {
        configList.append(PidConfig(ecu: ecu, request: request))
        if configList.count == 1 {
            startPoller()
        }
    }
    
    func removePidConfig(pidConfig: PidConfig) {
        configList.removeAll(where: { $0.id == pidConfig.id })
        if configList.count == 0 {
            stopPoller()
        }
    }
    
    func editPidConfig(pidConfig: PidConfig, ecu: String, request: String) {
        let index = configList.firstIndex(where: { $0.id == pidConfig.id })!
        configList[index].ecu = ecu
        configList[index].request = request
        objectWillChange.send()
    }
    
    func startPoller() {
        PidConfigManager.scope = CoScope()
        DispatchQueue.global().startCoroutine(in: PidConfigManager.scope) {
            while self.configList.count > 0 {
                for pidConfig in self.configList {
                    _ = try self.commander.sendCommandWithResponse("ATSH \(pidConfig.ecu)").await()
                    pidConfig.data = try self.commander.sendCommandWithResponse("\(pidConfig.request)").await().trimmingCharacters(in: .whitespacesAndNewlines)
                }

                DispatchQueue.main.sync {
                    self.objectWillChange.send()
                }
            }
        }
    }
    
    func stopPoller() {
        PidConfigManager.scope.cancel()
    }
}


enum ActivePidPollerSheet: Identifiable {
    case AddPid, EditPid
    
    var id: Int {
        hashValue
    }
}


enum ConnectingStatus: Identifiable {
    case NotConnected, Connecting, Detecting, Connected
    
    var id: Int {
        hashValue
    }
}


struct PidPollerAddConfigView: View {
    @ObservedObject var pidConfigManager: PidConfigManager
    var activeSheet: Binding<ActivePidPollerSheet?>
    
    @State private var addPidEcu: String = ""
    @State private var addPidRequest: String = ""
    
    var body: some View {
        VStack {
            HStack {
                Text("ECU: ")
                TextField("e.g. 7E0", text: $addPidEcu)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            HStack {
                Text("Request: ")
                TextField("e.g. 010D", text: $addPidRequest)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            HStack {
                Spacer()
                Button(action: {
                    pidConfigManager.addPidConfig(ecu: addPidEcu, request: addPidRequest)
                    activeSheet.wrappedValue = nil
                }) { Text ("Add") }
                    .padding()
            }
            Spacer()
        }
        .padding()
    }
}


struct PidPollerEditConfigView: View {
    @ObservedObject var pidConfigManager: PidConfigManager
    var activeSheet: Binding<ActivePidPollerSheet?>
    
    var editPid: Binding<PidConfig?>
    var editPidEcu: Binding<String>
    var editPidRequest: Binding<String>
    
    var body: some View {
        VStack {
            HStack {
                Text("ECU: ")
                TextField("e.g. 7E0", text: editPidEcu)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            HStack {
                Text("Request: ")
                TextField("e.g. 010D", text: editPidRequest)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            HStack {
                Button(action: {
                    pidConfigManager.removePidConfig(pidConfig: editPid.wrappedValue!)
                    editPid.wrappedValue = nil
                    activeSheet.wrappedValue = nil
                }) { Text ("Remove") }
                    .padding()
                Spacer()
                Button(action: {
                    pidConfigManager.editPidConfig(pidConfig: editPid.wrappedValue!, ecu: editPidEcu.wrappedValue, request: editPidRequest.wrappedValue)
                    activeSheet.wrappedValue = nil
                }) { Text ("Edit") }
                    .padding()
            }
            Spacer()
        }
        .padding()
    }
}


struct PidPollerView: View {
    @ObservedObject var bleManager: BleManager
    
    @ObservedObject var pidConfigManager: PidConfigManager
    
    @State private var activeSheet: ActivePidPollerSheet?
    
    @State private var editPid: PidConfig?
    @State private var editPidEcu: String = ""
    @State private var editPidRequest: String = ""
    
    var body: some View {
        VStack {
            
            Button(action: {
                activeSheet = .AddPid
            }) {
                Text("Add PID")
            }
            
            List(pidConfigManager.configList) { pidConfig in
                Button(action: {
                    editPid = pidConfig
                    editPidEcu = pidConfig.ecu
                    editPidRequest = pidConfig.request
                    activeSheet = .EditPid
                }) {
                    HStack {
                        Text(pidConfig.ecu).font(Font.system(.body, design: .monospaced))
                        Text(pidConfig.request).font(Font.system(.body, design: .monospaced))
                        Spacer()
                        Text(pidConfig.data).font(Font.system(.body, design: .monospaced))
                    }
                }
            }
        }
        
        .navigationTitle(Text("PID Poller"))
        
        .onAppear() {
            pidConfigManager.startPoller()
        }
        
        .onDisappear() {
            pidConfigManager.stopPoller()
            bleManager.cancelConnection()
        }
        
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .AddPid:
                PidPollerAddConfigView(
                    pidConfigManager: pidConfigManager,
                    activeSheet: $activeSheet
                )
            case .EditPid:
                PidPollerEditConfigView(
                    pidConfigManager: pidConfigManager,
                    activeSheet: $activeSheet,
                    editPid: $editPid,
                    editPidEcu: $editPidEcu,
                    editPidRequest: $editPidRequest
                )
            }

        }
    }
}


struct Divided<S: Shape>: Shape {
    var amount: CGFloat
    var shape: S
    func path(in rect: CGRect) -> Path {
        shape.path(in: rect.divided(atDistance: amount * rect.height, from: .maxYEdge).slice)
    }
}

extension Shape {
    func divided(amount: CGFloat) -> Divided<Self> {
        return Divided(amount: amount, shape: self)
    }
}

struct SignalStrengthIndicator: View {
    var rssi: Binding<Int>
    
    var totalBars: Int = 5
    
    func getBars() -> Int {
        if rssi.wrappedValue >= -30 {
            return 5
        } else if rssi.wrappedValue >= -67 {
            return 4
        } else if rssi.wrappedValue >= -70 {
            return 3
        } else if rssi.wrappedValue >= -80 {
            return 2
        } else if rssi.wrappedValue >= -90 {
            return 1
        } else {
            return 0
        }
    }
    
    
    var body: some View {
        HStack {
            let bars: Int = getBars()
            ForEach(0..<totalBars) { bar in
                RoundedRectangle(cornerRadius: 3)
                    .divided(amount: (CGFloat(bar) + 1) / CGFloat(self.totalBars))
                    .fill(Color.primary.opacity(bar < bars ? 1 : 0.3))
            }
        }
    }
}

struct ConnectingDialogView: View {
    var connectingStatus: Binding<ConnectingStatus>
    
    private var cancelCb: () -> ()
    
    init(connectingStatus: Binding<ConnectingStatus>, cancelCb: @escaping () -> ()) {
        self.connectingStatus = connectingStatus
        self.cancelCb = cancelCb
    }
    
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black)
                .opacity(0.5)
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(Color.white)
                .frame(width: 200, height: 200)
            VStack {
                switch connectingStatus.wrappedValue {
                case ConnectingStatus.Connecting:
                    Text("Connecting to CX")
                        .foregroundColor(.black)
                        .padding()
                case ConnectingStatus.Detecting:
                    Text("Detecting Protocol")
                        .foregroundColor(.black)
                        .padding()
                default:
                    EmptyView()
                }
                Spacer()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                Spacer()
                Button(action: {
                    self.cancelCb()
                }) {
                    Text("Cancel")
                }
                .padding()
            }
            .frame(width: 200, height: 200)
        }
    }
}


struct ContentView: View {
    @ObservedObject var bleManager = BleManager()
    
    @State var channel = CoChannel<Int>()
    
    var body: some View {
        ZStack {
            NavigationView {
                VStack {
                    List(bleManager.peripherals) { peripheral in
                        let index = bleManager.peripherals.firstIndex(where: {peripheral.id == $0.id})!
                        ZStack {
                            NavigationLink(
                                destination: PidPollerView(bleManager: bleManager, pidConfigManager: PidConfigManager(commander: peripheral)),
                                isActive: $bleManager.peripherals[index].isConnected) { EmptyView() }
                            Button(action: {
                                bleManager.peripherals[index].isConnected = false
                                bleManager.connectToPeripheral(id: peripheral.id)
                            }) {
                                HStack {
                                    Text("NNNNN").hidden().overlay(SignalStrengthIndicator(rssi: $bleManager.peripherals[index].rssi))
                                    Text(String(bleManager.peripherals[index].rssi))
                                    Text(bleManager.peripherals[index].name)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .onAppear() {
                    if bleManager.isSwitchedOn {
                        DispatchQueue.main.async {
                            bleManager.isScanning = true
                        }
                    }
                }
                .navigationBarTitle("Device List")
            }
            .navigationViewStyle(StackNavigationViewStyle())
            
            if bleManager.connectingStatus == .Connecting || bleManager.connectingStatus == .Detecting {
                ConnectingDialogView(connectingStatus: $bleManager.connectingStatus, cancelCb: {
                    bleManager.cancelConnection()
                })
            }
        }
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
