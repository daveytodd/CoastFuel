import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @StateObject private var service = FuelDataService()
    @StateObject private var locationManager = FuelLocationManager()
    @State private var selectedFuel: FuelType = .unleaded91
    @State private var selectedRadius: StationRadius = .tenKm
    @State private var showMap = false
    @State private var alertsEnabled = false
    @State private var selectedStation: FuelStation?

    private var stations: [FuelStation] {
        service.stations.filter { station in station.distanceKm <= selectedRadius.kilometers }
            .sorted { $0.distanceKm < $1.distanceKm }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
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
                locationManager.onLocationUpdate = { location in
                    service.setUserLocation(location)
                }
                locationManager.requestCurrentLocation()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        locationManager.requestCurrentLocation()
                    } label: {
                        Image(systemName: "location.fill")
                    }
                    .tint(.mint)
                    .accessibilityLabel("Refresh stations from current location")
                }
            }
        }
        .sheet(item: $selectedStation) { station in FuelStationDetailView(station: station) }
        .preferredColorScheme(.dark)
    }
}

@MainActor
private final class FuelLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onLocationUpdate: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestCurrentLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        onLocationUpdate?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Unable to obtain current location: \\(error.localizedDescription)")
    }
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
