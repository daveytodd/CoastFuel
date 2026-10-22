import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @StateObject private var service = FuelDataService()
    @StateObject private var locationManager = FuelLocationManager()
    @StateObject private var obdManager = OBDManager()
    @AppStorage("CoastFuel.tankCapacityLitres") private var tankCapacityLitres = 51.0
    @AppStorage("CoastFuel.averageConsumptionLitresPer100Km") private var averageConsumption = 7.0
    @State private var selectedFuel: FuelType = .unleaded91
    @State private var selectedRadius: StationRadius = .tenKm
    @State private var showMap = false
    @State private var alertsEnabled = false
    @State private var selectedStation: FuelStation?
    @State private var showVehicleSettings = false

    private var stations: [FuelStation] {
        service.stations.filter { $0.distanceKm <= selectedRadius.kilometers }.sorted { $0.distanceKm < $1.distanceKm }
    }
    private var rangeAdvisor: FuelRangeAdvisor {
        FuelRangeAdvisor(tankCapacityLitres: tankCapacityLitres, averageConsumptionLitresPer100Km: averageConsumption)
    }
    private var rangeRecommendation: FuelRangeAdvisor.Recommendation {
        rangeAdvisor.recommendation(fuelLevelPercentage: obdManager.fuelLevelPercentage, stations: service.stations, fuel: selectedFuel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                vehicleRangeCard.padding(.horizontal)
                HStack {
                    Picker("State", selection: $service.selectedState) {
                        ForEach(AustralianState.allCases) { state in Text(state.rawValue).tag(state) }
                    }.pickerStyle(.menu).tint(.mint).onChange(of: service.selectedState) { _, _ in service.refreshStations() }
                    Spacer()
                    Picker("Fuel", selection: $selectedFuel) { ForEach(FuelType.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).tint(.mint)
                }.padding(.horizontal)
                Picker("Search radius", selection: $selectedRadius) {
                    ForEach(StationRadius.allCases) { radius in Text(radius.title).tag(radius) }
                }.pickerStyle(.segmented).padding(.horizontal)
                Text("\(stations.count) stations within \(selectedRadius.title)").font(.caption).foregroundStyle(.secondary)
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
                    List(stations) { station in Button { selectedStation = station } label: { StationRow(station: station, fuel: selectedFuel) }.buttonStyle(.plain) }.listStyle(.plain)
                }
            }
            .background(Color.black).navigationTitle("CoastFuel").task {
                await service.load()
                locationManager.onLocationUpdate = { location in service.setUserLocation(location) }
                locationManager.requestCurrentLocation()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { locationManager.requestCurrentLocation() } label: { Image(systemName: "location.fill") }.tint(.mint).accessibilityLabel("Refresh stations from current location")
                }
            }
        }
        .sheet(item: $selectedStation) { station in FuelStationDetailView(station: station) }
        .sheet(isPresented: $showVehicleSettings) { vehicleSettings }
        .preferredColorScheme(.dark)
    }

    private var vehicleRangeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Vehicle fuel range", systemImage: "fuelpump.fill").font(.headline)
                Spacer()
                Circle().fill(obdManager.isVehicleRunning ? .green : (obdManager.isConnected ? .orange : .gray)).frame(width: 9, height: 9)
                Text(obdManager.isVehicleRunning ? "Engine Running" : (obdManager.isConnected ? "Engine Off" : "Disconnected"))
                    .font(.caption.bold()).foregroundStyle(.secondary)
                Menu {
                    if obdManager.isConnected { Button("Disconnect OBD-II", role: .destructive) { obdManager.disconnect() } }
                    else {
                        Button("Scan for OBD-II adapter") { obdManager.startScanning() }
                        ForEach(obdManager.discoveredAdapters, id: \.identifier) { peripheral in
                            Button(peripheral.name ?? "OBD-II adapter") { obdManager.connect(to: peripheral) }
                        }
                    }
                    Button("Vehicle profile settings") { showVehicleSettings = true }
                } label: { Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.mint) }
                .accessibilityLabel("OBD and vehicle settings")
            }
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                VStack(alignment: .leading) {
                    Text("Fuel level").font(.caption).foregroundStyle(.secondary)
                    Text(obdManager.fuelLevelPercentage.map { String(format: "%.0f%%", $0) } ?? "—").font(.title2.bold())
                }
                VStack(alignment: .leading) {
                    Text("Estimated range").font(.caption).foregroundStyle(.secondary)
                    Text(rangeAdvisor.estimatedRangeKm(fuelLevelPercentage: obdManager.fuelLevelPercentage).map { String(format: "%.0f km", $0) } ?? "—").font(.title2.bold()).foregroundStyle(.mint)
                }
            }
            Text(rangeRecommendation.text).font(.subheadline).foregroundStyle(rangeRecommendation.isLowFuel ? .orange : .white).fixedSize(horizontal: false, vertical: true)
            Text(String(format: "Vehicle profile: %.0f L tank · %.1f L/100 km", tankCapacityLitres, averageConsumption)).font(.caption2).foregroundStyle(.secondary)
            if obdManager.isVehicleRunning { Button("Refresh fuel level") { obdManager.requestFuelLevel() }.font(.caption.bold()).tint(.mint) }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 16))
    }

    private var vehicleSettings: some View {
        NavigationStack {
            Form {
                Section("Vehicle profile") {
                    HStack { Text("Tank capacity"); Spacer(); TextField("Litres", value: $tankCapacityLitres, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing); Text("L") }
                    HStack { Text("Average consumption"); Spacer(); TextField("L/100 km", value: $averageConsumption, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing); Text("L/100 km") }
                }
                Section { Text("These settings are saved on this device and used to estimate range for the connected car.").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Vehicle profile")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showVehicleSettings = false }.tint(.mint) } }
            .preferredColorScheme(.dark)
        }
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
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { if let location = locations.last { onLocationUpdate?(location) } }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { print("Unable to obtain current location: \(error.localizedDescription)") }
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
                Text("\(station.distanceKm, specifier: "%.1f") km · \(station.amenities.joined(separator: " · "))").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(station.prices[fuel].map { String(format: "%.1f¢", $0) } ?? "—").font(.title3.bold()).foregroundStyle(.mint)
        }.listRowBackground(Color(white: 0.07)).padding(.vertical, 5).contentShape(Rectangle())
    }
}

private struct FuelStationDetailView: View {
    let station: FuelStation
    @Environment(\.dismiss) private var dismiss
    private var orderedPrices: [(fuel: FuelType, price: Double)] { FuelType.allCases.compactMap { fuel in station.prices[fuel].map { (fuel, $0) } }
    var body: some View {
        NavigationStack {
            List {
                Section(station.name) {
                    Text(station.address)
                    Text(String(format: "%.1f km away", station.distanceKm))
                    ForEach(orderedPrices, id: \.fuel) { entry in HStack { Text(entry.fuel.rawValue); Spacer(); Text(String(format: "%.1f¢/L", entry.price)).foregroundStyle(.mint) } }
                }
                Section("Amenities") { ForEach(station.amenities, id: \.self) { Text($0) } }
                Section { Button("Open in Apple Maps") {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate.location)); item.name = station.name
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                } }
            }.navigationTitle("Station details").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.tint(.mint) } }
        }.preferredColorScheme(.dark)
    }
}
