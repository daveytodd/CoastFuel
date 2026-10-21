import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var service = FuelDataService()
    @State private var selectedFuel: FuelType = .unleaded91
    @State private var selectedRadius: StationRadius = .tenKm
    @State private var showMap = false
    @State private var alertsEnabled = false
    @State private var selectedStation: FuelStation?

    private var stations: [FuelStation] {
        service.stations.filter { station in selectedRadius.kilometers.map { station.distanceKm <= $0 } ?? true }
            .sorted { ($0.prices[selectedFuel] ?? .infinity) < ($1.prices[selectedFuel] ?? .infinity) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Fuel", selection: $selectedFuel) { ForEach(FuelType.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).tint(.mint).padding(.horizontal)
                Picker("Search radius", selection: $selectedRadius) {
                    ForEach(StationRadius.allCases) { radius in Text(radius.title).tag(radius) }
                }.pickerStyle(.segmented).padding(.horizontal)
                    .onChange(of: selectedRadius) { _, radius in UserDefaults.standard.set(radius.rawValue, forKey: "stationRadius") }
                Text("\(stations.count) stations within \(selectedRadius.title)").font(.caption).foregroundStyle(.secondary)
                Toggle(isOn: $showMap) { Label(showMap ? "Map" : "Stations", systemImage: showMap ? "map" : "list.bullet") }.padding(.horizontal)
                Toggle("Price alerts", isOn: $alertsEnabled).tint(.mint).padding(.horizontal)
                if showMap {
                    Map {
                        ForEach(stations) { station in
                            Annotation(station.name, coordinate: station.coordinate.location) {
                                Button { selectedStation = station } label: {
                                    Text(station.prices[selectedFuel].map { String(format: "%.1f¢", $0) } ?? "—")
                                        .font(.caption.bold()).padding(7).background(.mint, in: Circle()).foregroundStyle(.black)
                                }.buttonStyle(.plain).accessibilityLabel("\(station.name), view station details")
                            }
                        }
                    }.mapStyle(.standard(elevation: .realistic)).clipShape(RoundedRectangle(cornerRadius: 18)).padding()
                } else {
                    List(stations) { station in
                        Button { selectedStation = station } label: { StationRow(station: station, fuel: selectedFuel) }
                            .buttonStyle(.plain)
                    }.listStyle(.plain)
                }
            }
            .background(Color.black).navigationTitle("CoastFuel").task {
                if let saved = UserDefaults.standard.string(forKey: "stationRadius"), let radius = StationRadius(rawValue: saved) { selectedRadius = radius }
                await service.load()
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await service.load() } } label: { Image(systemName: "arrow.clockwise") }.tint(.mint) } }
        }
        .sheet(item: $selectedStation) { station in FuelStationDetailView(station: station) }
        .preferredColorScheme(.dark)
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

    private var orderedPrices: [(fuel: FuelType, price: Double)] {
        FuelType.allCases.compactMap { fuel in station.prices[fuel].map { (fuel, $0) } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(station.name, systemImage: "fuelpump.fill").font(.title2.bold()).foregroundStyle(.white)
                        Label(station.address, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(.secondary)
                        Label(String(format: "%.1f km away", station.distanceKm), systemImage: "location").font(.subheadline).foregroundStyle(.secondary)
                        Button(action: openDirections) {
                            Label("Open in Apple Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.headline).frame(maxWidth: .infinity).padding()
                                .background(.mint, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.black)
                        }.buttonStyle(.plain).padding(.top, 6)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Fuel prices").font(.headline)
                        if orderedPrices.isEmpty {
                            Text("No fuel prices available").foregroundStyle(.secondary)
                        } else {
                            ForEach(orderedPrices, id: \.fuel) { entry in
                                HStack {
                                    Text(entry.fuel.rawValue).foregroundStyle(.white)
                                    Spacer()
                                    Text(String(format: "%.1f¢/L", entry.price)).font(.headline.monospacedDigit()).foregroundStyle(.mint)
                                }.padding(12).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Amenities & services").font(.headline)
                        let amenities = station.amenities.isEmpty ? ["Fuel", "Air & Water", "Convenience Store"] : station.amenities
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), alignment: .leading)], alignment: .leading, spacing: 10) {
                            ForEach(amenities, id: \.self) { amenity in
                                Label(amenity, systemImage: Self.symbol(for: amenity))
                                    .font(.caption.weight(.medium)).padding(.horizontal, 11).padding(.vertical, 9)
                                    .background(Color.mint.opacity(0.14), in: Capsule()).foregroundStyle(.mint)
                            }
                        }
                    }
                }.padding(20)
            }
            .background(Color.black)
            .navigationTitle("Station details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.tint(.mint) } }
        }.preferredColorScheme(.dark)
    }

    private func openDirections() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: station.coordinate.location))
        item.name = station.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private static func symbol(for amenity: String) -> String {
        let value = amenity.lowercased()
        if value.contains("coffee") || value.contains("cafe") { return "cup.and.saucer.fill" }
        if value.contains("convenience") || value.contains("store") { return "basket.fill" }
        if value.contains("wash") { return "car_wash" }
        if value.contains("restroom") || value.contains("toilet") { return "figure.dress.line.vertical.figure" }
        if value.contains("air") || value.contains("water") { return "wind" }
        if value.contains("atm") { return "banknote.fill" }
        if value.contains("24") || value.contains("pay") { return "clock.fill" }
        if value.contains("ev") || value.contains("charging") { return "bolt.car.fill" }
        if value.contains("trailer") { return "caravan.fill" }
        return "checkmark.circle.fill"
    }
}
