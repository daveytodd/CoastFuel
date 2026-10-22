import SwiftUI
import MapKit
import CoreLocation

struct ContentView: View {
    @StateObject private var service = FuelDataService()
    @StateObject private var locationManager = FuelLocationManager()
    @StateObject private var obdManager = OBDManager()
    @StateObject private var profileStore = VehicleProfileStore()
    @State private var selectedFuel: FuelType = .unleaded91
    @State private var selectedRadius: StationRadius = .tenKm
    @State private var showMap = false
    @State private var alertsEnabled = false
    @State private var selectedStation: FuelStation?
    @State private var showVehicleSettings = false

    private var stations: [FuelStation] { service.stations.filter { $0.distanceKm <= selectedRadius.kilometers }.sorted { $0.distanceKm < $1.distanceKm } }
    private var rangeAdvisor: FuelRangeAdvisor { FuelRangeAdvisor(profile: profileStore.activeProfile) }
    private var rangeRecommendation: FuelRangeAdvisor.Recommendation { rangeAdvisor.recommendation(fuelLevelPercentage: obdManager.fuelLevelPercentage, stations: service.stations) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                vehicleRangeCard.padding(.horizontal)
                HStack {
                    Picker("State", selection: $service.selectedState) { ForEach(AustralianState.allCases) { state in Text(state.rawValue).tag(state) } }.pickerStyle(.menu).tint(.mint).onChange(of: service.selectedState) { _, _ in service.refreshStations() }
                    Spacer()
                    Picker("Fuel", selection: $selectedFuel) { ForEach(FuelType.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).tint(.mint)
                }.padding(.horizontal)
                Picker("Search radius", selection: $selectedRadius) { ForEach(StationRadius.allCases) { radius in Text(radius.title).tag(radius) } }.pickerStyle(.segmented).padding(.horizontal)
                Text("\(stations.count) stations within \(selectedRadius.title)").font(.caption).foregroundStyle(.secondary)
                Toggle(isOn: $showMap) { Label(showMap ? "Map" : "Stations", systemImage: showMap ? "map" : "list.bullet") }.padding(.horizontal)
                Toggle("Price alerts", isOn: $alertsEnabled).tint(.mint).padding(.horizontal)
                if showMap {
                    Map { ForEach(stations) { station in Annotation(station.name, coordinate: station.coordinate.location) { Button { selectedStation = station } label: { Text(station.prices[selectedFuel].map { String(format: "%.1f¢", $0) } ?? "—").font(.caption.bold()).padding(7).background(.mint, in: Circle()).foregroundStyle(.black) }.buttonStyle(.plain) } } }.mapStyle(.standard(elevation: .realistic)).clipShape(RoundedRectangle(cornerRadius: 18)).padding()
                } else { List(stations) { station in Button { selectedStation = station } label: { StationRow(station: station, fuel: selectedFuel) }.buttonStyle(.plain) }.listStyle(.plain) }
            }
            .background(Color.black).navigationTitle("CoastFuel").task { await service.load(); locationManager.onLocationUpdate = { location in service.setUserLocation(location) }; locationManager.requestCurrentLocation() }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { locationManager.requestCurrentLocation() } label: { Image(systemName: "location.fill") }.tint(.mint).accessibilityLabel("Refresh stations from current location") } }
        }
        .sheet(item: $selectedStation) { station in FuelStationDetailView(station: station) }
        .sheet(isPresented: $showVehicleSettings) { VehicleProfilesView(store: profileStore) }
        .preferredColorScheme(.dark)
    }

    private var vehicleRangeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profileStore.activeProfile.name).font(.headline)
                    Text("\(profileStore.activeProfile.fuelType.rawValue) · \(profileStore.activeProfile.tankCapacityLitres, specifier: "%.1f") L tank · \(profileStore.activeProfile.averageConsumptionLitresPer100Km, specifier: "%.1f") L/100 km").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(obdManager.isVehicleRunning ? .green : (obdManager.isConnected ? .orange : .gray)).frame(width: 9, height: 9)
                Text(obdManager.isVehicleRunning ? "Engine Running" : (obdManager.isConnected ? "Engine Off" : "Disconnected")).font(.caption.bold()).foregroundStyle(.secondary)
                Menu {
                    if obdManager.isConnected { Button("Disconnect OBD-II", role: .destructive) { obdManager.disconnect() } }
                    else { Button("Scan for OBD-II adapter") { obdManager.startScanning() }; ForEach(obdManager.discoveredAdapters, id: \.identifier) { peripheral in Button(peripheral.name ?? "OBD-II adapter") { obdManager.connect(to: peripheral) } } }
                    Button("Manage vehicle profiles") { showVehicleSettings = true }
                } label: { Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.mint) }.accessibilityLabel("OBD and vehicle profile settings")
            }
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                VStack(alignment: .leading) { Text("Fuel level").font(.caption).foregroundStyle(.secondary); Text(obdManager.fuelLevelPercentage.map { String(format: "%.0f%%", $0) } ?? "—").font(.title2.bold()) }
                VStack(alignment: .leading) { Text("Estimated range").font(.caption).foregroundStyle(.secondary); Text(rangeAdvisor.estimatedRangeKm(fuelLevelPercentage: obdManager.fuelLevelPercentage).map { String(format: "%.0f km", $0) } ?? "—").font(.title2.bold()).foregroundStyle(.mint) }
                Spacer()
                Menu("Switch") { ForEach(profileStore.profiles) { profile in Button { profileStore.select(profile.id) } label: { if profile.id == profileStore.activeProfileID { Label(profile.name, systemImage: "checkmark") } else { Text(profile.name) } } }; Button("Add or edit profiles…") { showVehicleSettings = true } }.font(.caption).tint(.mint)
            }
            Text(rangeRecommendation.text).font(.subheadline).foregroundStyle(rangeRecommendation.isLowFuel ? .orange : .white).fixedSize(horizontal: false, vertical: true)
            if obdManager.isVehicleRunning { Button("Refresh fuel level") { obdManager.requestFuelLevel() }.font(.caption.bold()).tint(.mint) }
            if !obdManager.isConnected { adapterRecommendation }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 16))
    }

    private var adapterRecommendation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Don't have an OBD-II adapter? Get a compatible Bluetooth scanner to unlock live fuel levels and smart range alerts.").font(.caption).fixedSize(horizontal: false, vertical: true)
            Link(destination: URL(string: "https://www.amazon.com.au/s?k=ELM327+bluetooth+4.0+OBD2&tag=daveytodd-22")!) { Label("Shop ELM327 Bluetooth adapters on Amazon AU", systemImage: "arrow.up.right.square").font(.caption.bold()) }.tint(.mint)
            Text("As an Amazon Associate, Dave may earn from qualifying purchases.").font(.caption2).foregroundStyle(.secondary)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct VehicleProfilesView: View {
    @ObservedObject var store: VehicleProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingProfile: VehicleProfile?
    @State private var isCreating = false
    var body: some View {
        NavigationStack {
            List {
                Section("Active vehicle") {
                    Picker("Select profile", selection: Binding(get: { store.activeProfileID }, set: { store.select($0) })) { ForEach(store.profiles) { profile in Text(profile.name).tag(profile.id) } }
                    Text("\(store.activeProfile.fuelType.rawValue) · \(store.activeProfile.tankCapacityLitres, specifier: "%.1f") L · \(store.activeProfile.averageConsumptionLitresPer100Km, specifier: "%.1f") L/100 km").font(.caption).foregroundStyle(.secondary)
                }
                Section("Saved profiles") {
                    ForEach(store.profiles) { profile in HStack { VStack(alignment: .leading) { Text(profile.name); Text("\(profile.fuelType.rawValue) · \(profile.tankCapacityLitres, specifier: "%.1f") L · \(profile.averageConsumptionLitresPer100Km, specifier: "%.1f") L/100 km").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Edit") { editingProfile = profile }.buttonStyle(.borderless) } }
                    .onDelete { offsets in offsets.map { store.profiles[$0].id }.forEach { store.delete($0) } }
                    Button { isCreating = true } label: { Label("Add vehicle profile", systemImage: "plus") }
                }
            }
            .scrollContentBackground(.hidden).background(Color.black)
            .navigationTitle("Vehicle profiles").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $isCreating) { VehicleProfileEditor(profile: nil, onSave: store.add) }
            .sheet(item: $editingProfile) { profile in VehicleProfileEditor(profile: profile, onSave: store.update) }
        }.preferredColorScheme(.dark)
    }
}

private struct VehicleProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var fuelType: FuelType
    @State private var tankCapacity: Double
    @State private var consumption: Double
    private let existing: VehicleProfile?
    private let onSave: (VehicleProfile) -> Void
    init(profile: VehicleProfile?, onSave: @escaping (VehicleProfile) -> Void) {
        existing = profile; self.onSave = onSave; _name = State(initialValue: profile?.name ?? "My Car"); _fuelType = State(initialValue: profile?.fuelType ?? .unleaded91); _tankCapacity = State(initialValue: profile?.tankCapacityLitres ?? 51); _consumption = State(initialValue: profile?.averageConsumptionLitresPer100Km ?? 7)
    }
    var body: some View {
        NavigationStack {
            Form { Section("Vehicle details") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Vehicle name").font(.caption).foregroundStyle(.secondary)
                    TextField("e.g. Dave’s Mazda 3", text: $name).textInputAutocapitalization(.words).autocorrectionDisabled().submitLabel(.done)
                        .accessibilityLabel("Vehicle nickname")
                }.padding(.vertical, 4)
                Picker("Fuel type", selection: $fuelType) { ForEach(FuelType.allCases) { fuel in Text(fuel.rawValue).tag(fuel) } }
                HStack { Text("Tank capacity"); Spacer(); TextField("Litres", value: $tankCapacity, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing); Text("L") }
                HStack { Text("Fuel economy"); Spacer(); TextField("L/100 km", value: $consumption, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing); Text("L/100 km") }
            } }.scrollContentBackground(.hidden).background(Color.black)
            .navigationTitle(existing == nil ? "Add Vehicle" : "Edit Vehicle")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") {
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let profile = VehicleProfile(id: existing?.id ?? UUID(), name: trimmedName, fuelType: fuelType, tankCapacityLitres: tankCapacity, averageConsumptionLitresPer100Km: consumption, obdAdapterUUID: existing?.obdAdapterUUID)
                onSave(profile); dismiss()
            }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || tankCapacity <= 0 || consumption <= 0) } }
        }.preferredColorScheme(.dark)
    }
}

@MainActor
private final class FuelLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onLocationUpdate: ((CLLocation) -> Void)?
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest }
    func requestCurrentLocation() { switch manager.authorizationStatus { case .notDetermined: manager.requestWhenInUseAuthorization(); case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation(); case .denied, .restricted: break; @unknown default: break } }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() } }
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
        HStack(spacing: 14) { Image(systemName: "fuelpump.fill").foregroundStyle(.mint).font(.title2); VStack(alignment: .leading, spacing: 5) { Text(station.name).font(.headline).foregroundStyle(.white); Text(station.address).font(.caption).foregroundStyle(.secondary); Text("\(station.distanceKm, specifier: "%.1f") km · \(station.amenities.joined(separator: " · "))").font(.caption2).foregroundStyle(.secondary) }; Spacer(); Text(station.prices[fuel].map { String(format: "%.1f¢", $0) } ?? "—").font(.title3.bold()).foregroundStyle(.mint) }.listRowBackground(Color(white: 0.07)).padding(.vertical, 5).contentShape(Rectangle())
    }
}

private struct FuelStationDetailView: View {
    let station: FuelStation
    @Environment(\.dismiss) private var dismiss
    private var orderedPrices: [(fuel: FuelType, price: Double)] { FuelType.allCases.compactMap { fuel in station.prices[fuel].map { (fuel, $0) } } }
    var body: some View {
        NavigationStack {
            List { Section(station.name) { Text(station.address); Text(String(format: "%.1f km away", station.distanceKm)); ForEach(orderedPrices, id: \.fuel) { entry in HStack { Text(entry.fuel.rawValue); Spacer(); Text(String(format: "%.1f¢/L", entry.price)).foregroundStyle(.mint) } } }; Section("Amenities") { ForEach(station.amenities, id: \.self) { Text($0) } }; Section { Button("Open in Apple Maps") { let item = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate.location)); item.name = station.name; item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]) } } }.navigationTitle("Station details").toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.tint(.mint) } }
        }.preferredColorScheme(.dark)
    }
}
