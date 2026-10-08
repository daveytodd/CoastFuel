import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var service = FuelDataService()
    @StateObject private var obdManager = OBDManager()
    @State private var selectedFuel: FuelType = .unleaded91
    @State private var selectedRadius: StationRadius = .tenKm
    @State private var showMap = false
    @State private var alertsEnabled = false

    private var stations: [FuelStation] {
        service.stations.filter { station in selectedRadius.kilometers.map { station.distanceKm <= $0 } ?? true }
            .sorted { ($0.prices[selectedFuel] ?? .infinity) < ($1.prices[selectedFuel] ?? .infinity) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                scannerCard
                Picker("Fuel", selection: $selectedFuel) { ForEach(FuelType.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).tint(.mint).padding(.horizontal)
                Picker("Search radius", selection: $selectedRadius) {
                    ForEach(StationRadius.allCases) { radius in Text(radius.title).tag(radius) }
                }.pickerStyle(.segmented).padding(.horizontal)
                    .onChange(of: selectedRadius) { _, radius in UserDefaults.standard.set(radius.rawValue, forKey: "stationRadius") }
                Text("\(stations.count) stations within \(selectedRadius.title)").font(.caption).foregroundStyle(.secondary)
                Toggle(isOn: $showMap) { Label(showMap ? "Map" : "Stations", systemImage: showMap ? "map" : "list.bullet") }.padding(.horizontal)
                Toggle("Price alerts", isOn: $alertsEnabled).tint(.mint).padding(.horizontal)
                if showMap {
                    Map { ForEach(stations) { station in
                        Annotation(station.name, coordinate: station.coordinate.location) {
                            Text(station.prices[selectedFuel].map { String(format:"%.1f¢",$0) } ?? "—")
                                .font(.caption.bold()).padding(7).background(.mint,in:Circle()).foregroundStyle(.black)
                        }
                    }}.mapStyle(.standard(elevation:.realistic)).clipShape(RoundedRectangle(cornerRadius:18)).padding()
                } else {
                    List(stations) { station in StationRow(station: station, fuel: selectedFuel) }.listStyle(.plain)
                }
            }
            .background(Color.black).navigationTitle("CoastFuel").task {
                if let saved = UserDefaults.standard.string(forKey: "stationRadius"), let radius = StationRadius(rawValue: saved) { selectedRadius = radius }
                await service.load()
            }
            .task(id: obdManager.isConnected) {
                while obdManager.isConnected {
                    obdManager.requestFuelLevel()
                    try? await Task.sleep(for: .seconds(15))
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await service.load() } } label: { Image(systemName:"arrow.clockwise") }.tint(.mint) } }
        }.preferredColorScheme(.dark)
    }

    private var scannerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: obdManager.isConnected ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                    .foregroundStyle(obdManager.isConnected ? .green : .mint)
                Text("OBD-II Scanner").font(.headline)
                Spacer()
                Text(scannerStatus).font(.subheadline).foregroundStyle(statusColor)
            }
            if obdManager.isConnected {
                if let level = obdManager.fuelLevelPercentage {
                    HStack {
                        Text("Fuel level").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(level, specifier: "%.0f")%").font(.title2.bold()).foregroundStyle(.mint)
                    }
                    ProgressView(value: min(max(obdManager.fuelLevelPercentage ?? 0, 0), 100), total: 100).tint(.mint)
                    Text(obdManager.lastFuelReadAt.map { "Last read " + $0.formatted(date: .omitted, time: .shortened) } ?? "Waiting for first reading")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Connected; waiting for a fuel-level reading.").font(.caption).foregroundStyle(.secondary)
                }
                Button("Disconnect", systemImage: "xmark.circle") { obdManager.disconnect() }
                    .buttonStyle(.bordered).tint(.red)
            } else {
                Button(obdManager.connectionState == .scanning ? "Stop scanning" : "Scan for adapters",
                       systemImage: obdManager.connectionState == .scanning ? "stop.circle" : "magnifyingglass") {
                    if obdManager.connectionState == .scanning { obdManager.stopScanning() }
                    else { obdManager.startScanning() }
                }.buttonStyle(.borderedProminent).tint(.mint)
                    .disabled(obdManager.connectionState == .connecting || obdManager.connectionState == .discovering || obdManager.connectionState == .initializing)
                ForEach(obdManager.discoveredAdapters, id: \.identifier) { peripheral in
                    Button { obdManager.connect(to: peripheral) } label: {
                        Label(peripheral.name ?? "BLE OBD-II adapter", systemImage: "dot.radiowaves.left.and.right")
                    }.buttonStyle(.bordered).tint(.mint)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var scannerStatus: String {
        switch obdManager.connectionState {
        case .idle: return "Disconnected"
        case .scanning: return "Scanning"
        case .connecting, .discovering, .initializing: return "Connecting"
        case .ready: return "Connected"
        case .failed: return "Error"
        }
    }

    private var statusColor: Color {
        switch obdManager.connectionState {
        case .ready: return .green
        case .failed: return .red
        default: return .secondary
        }
    }
}

enum StationRadius: String, CaseIterable, Identifiable {
    case fiveKm, tenKm, twentyFiveKm, fiftyKm, all
    var id: String { rawValue }
    var title: String { switch self { case .fiveKm: "5 km"; case .tenKm: "10 km"; case .twentyFiveKm: "25 km"; case .fiftyKm: "50 km"; case .all: "All" } }
    var kilometers: Double? { switch self { case .fiveKm: 5; case .tenKm: 10; case .twentyFiveKm: 25; case .fiftyKm: 50; case .all: nil } }
}

private struct StationRow: View {
    let station: FuelStation
    let fuel: FuelType
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName:"fuelpump.fill").foregroundStyle(.mint).font(.title2)
            VStack(alignment:.leading,spacing:5) {
                Text(station.name).font(.headline).foregroundStyle(.white)
                Text(station.address).font(.caption).foregroundStyle(.secondary)
                Text("\(station.distanceKm, specifier:"%.1f") km · \(station.amenities.joined(separator:" · "))").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(station.prices[fuel].map { String(format:"%.1f¢",$0) } ?? "—").font(.title3.bold()).foregroundStyle(.mint)
        }.listRowBackground(Color(white:0.07)).padding(.vertical,5)
    }
}
