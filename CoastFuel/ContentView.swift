import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @StateObject private var service = FuelDataService()
    @StateObject private var locationManager = FuelLocationManager()
    @StateObject private var obdManager = OBDManager()
    @State private var selectedFuel: FuelType = .unleaded91
    @State private var selectedRadius: StationRadius = .tenKm
    @State private var showMap = false
    @State private var alertsEnabled = false
    @State private var selectedStation: FuelStation?
    private let fuelRangeAdvisor = FuelRangeAdvisor()

    private var stations: [FuelStation] {
        service.stations.filter { $0.distanceKm <= selectedRadius.kilometers }.sorted { $0.distanceKm < $1.distanceKm }
    }
    private var fuelRecommendation: FuelRangeAdvisor.Recommendation? {
        fuelRangeAdvisor.recommendation(fuelLevelPercentage: obdManager.fuelLevelPercentage, stations: service.stations, fuel: selectedFuel)
    }
    private var obdStatus: String {
        guard obdManager.isConnected else { return "Disconnected" }
        return obdManager.isVehicleRunning ? "Engine Running" : "Engine Off"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                obdCard
                HStack {
                    Picker("State", selection: $service.selectedState) {
                        ForEach(AustralianState.allCases) { state in Text(state.rawValue).tag(state) }
                    }.pickerStyle(.menu).tint(.mint)
                        .onChange(of: service.selectedState) { _, _ in service.refreshStations() }
                    Spacer()
                    Picker("Fuel", selection: $selectedFuel) { ForEach(FuelType.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).tint(.mint)
                }.padding(.horizontal)
                Picker("Search radius", selection: $selectedRadius) {
                    ForEach(StationRadius.allCases) { radius in Text(radius.title).tag(radius) }
                }.pickerStyle(.segmented).padding(.horizontal)
                Text("\\(stations.count) stations within \\(selectedRadius.title)").font(.caption).foregroundStyle(.secondary)
                Toggle(isOn: $showMap) { Label(showMap ? "Map" : "Stations", systemImage: showMap ? "map" : "list.bullet") }.padding(.horizontal)
                Toggle("Price alerts", isOn: $alertsEnabled).tint(.mint).padding(.horizontal)
                if showMap {
                    Map { ForEach(stations) { station in
                        Annotation(station.name, coordinate: station.coordinate.location) {
                            Button { selectedStation = station } label: {
                                Text(station.prices[selectedFuel].map { String(format: "%.1f¢", $0) } ?? "—").font(.caption.bold()).padding(7).background(.mint, in: Circle()).foregroundStyle(.black)
                            }.buttonStyle(.plain)
                        }
                    }}.mapStyle(.standard(elevation: .realistic)).clipShape(RoundedRectangle(cornerRadius: 18)).padding()
                } else {
                    List(stations) { station in
                        Button { selectedStation = station } label: { StationRow(station: station, fuel: selectedFuel) }.buttonStyle(.plain)
                    }.listStyle(.plain)
                }
            }
            .background(Color.black).navigationTitle("CoastFuel").task {
                await service.load()
                locationManager.onLocationUpdate = { location in service.setUserLocation(location) }
                locationManager.requestCurrentLocation()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { locationManager.requestCurrentLocation() } label: { Image(systemName: "location.fill") }
                        .tint(.mint).accessibilityLabel("Refresh stations from current location")
                }
            }
        }
        .sheet(item: $selectedStation) { station in FuelStationDetailView(station: station) }
        .preferredColorScheme(.dark)
    }

    private var obdCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(obdStatus, systemImage: obdManager.isConnected ? (obdManager.isVehicleRunning ? "car.fill" : "car") : "bolt.slash.fill")
                    .font(.headline).foregroundStyle(obdManager.isConnected ? .mint : .secondary)
                Spacer()
                if obdManager.isConnected {
                    Button("Disconnect") { obdManager.disconnect() }.tint(.orange)
                } else {
                    Button(obdManager.connectionState == .scanning ? "Scanning…" : "Connect") {
                        obdManager.startScanning()
                    }.tint(.mint)
                    .disabled(obdManager.connectionState == .scanning || obdManager.connectionState == .connecting || obdManager.connectionState == .discovering || obdManager.connectionState == .initializing)
                }
            }
            HStack {
                metric(title: "Fuel", value: obdManager.fuelLevelPercentage.map { String(format: "%.0f%%", $0) } ?? "—")
                Spacer()
                metric(title: "Estimated range", value: fuelRecommendation.map { String(format: "%.0f km", $0.rangeKm) } ?? "—")
                if obdManager.isConnected && obdManager.isVehicleRunning {
                    Button { obdManager.requestFuelLevel() } label: { Image(systemName: "arrow.clockwise") }.tint(.mint).accessibilityLabel("Refresh fuel level")
                }
            }
            Text(fuelRecommendation?.text ?? (obdManager.isConnected ? "Waiting for live fuel level…" : "Connect an OBD-II adapter for live fuel advice."))
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(14).background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal)
        .onChange(of: obdManager.isConnected) { _, connected in if connected { obdManager.requestFuelLevel() } }
        .onChange(of: obdManager.isVehicleRunning) { _, running in if running { obdManager.requestFuelLevel() } }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title3.bold()).foregroundStyle(.white) }
    }
}

@MainActor
private final class FuelLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onLocationUpdate: ((CLLocation) -> Void)?
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest }
    func requestCurrentLocation() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: break
        @unknown default: break
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }; onLocationUpdate?(location)
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { print("Unable to obtain current location: \\(error.localizedDescription)") }
}

enum StationRadius: String, CaseIterable, Identifiable {
    case fiveKm, tenKm, twentyFiveKm, fiftyKm
    var id: String { rawValue }
    var title: String { switch self { case .fiveKm: "5 km"; case .tenKm: "10 km"; case .twentyFiveKm: "25 km"; case .fiftyKm: "50 km" } }
    var kilometers: Double { switch self { case .fiveKm: 5; case .tenKm: 10; case .twentyFiveKm: 25; case .fiftyKm: 50 } }
}

private struct StationRow: View {
    let station: FuelStation
    let fuel: FuelType
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "fuelpump.fill").foregroundStyle(.mint).font(.title2)
            VStack(alignment: .leading, spacing: 5) {
                Text(station.name).font(.headline).foregroundStyle(.white)
                Text(station.address).font(.caption).foregroundStyle(.secondary)
                Text("\\(station.distanceKm, specifier: "%.1f") km · \\(station.amenities.joined(separator: " · "))").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(station.prices[fuel].map { String(format: "%.1f¢", $0) } ?? "—").font(.title3.bold()).foregroundStyle(.mint)
        }.listRowBackground(Color(white: 0.07)).padding(.vertical, 5).contentShape(Rectangle())
    }
}

private struct FuelStationDetailView: View {
    let station: FuelStation
    @Environment(\\.dismiss) private var dismiss
    private var orderedPrices: [(fuel: FuelType, price: Double)] { FuelType.allCases.compactMap { fuel in station.prices[fuel].map { (fuel, $0) } } }
    var body: some View {
        NavigationStack {
            List {
                Section(station.name) {
                    Text(station.address)
                    Text(String(format: "%.1f km away", station.distanceKm))
                    ForEach(orderedPrices, id: \\.fuel) { entry in HStack { Text(entry.fuel.rawValue); Spacer(); Text(String(format: "%.1f¢/L", entry.price)).foregroundStyle(.mint) } }
                }
                Section("Amenities") { ForEach(station.amenities, id: \\.self) { Text($0) } }
                Section { Button("Open in Apple Maps") {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate.location)); item.name = station.name
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                } }
            }.navigationTitle("Station details").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.tint(.mint) } }
        }.preferredColorScheme(.dark)
    }
}
