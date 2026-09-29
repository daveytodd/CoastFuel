import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var service = FuelDataService()
    @State private var selectedFuel: FuelType = .unleaded91
    @State private var showMap = false
    @State private var alertsEnabled = false
    private var stations: [FuelStation] { service.stations.sorted { ($0.prices[selectedFuel] ?? .infinity) < ($1.prices[selectedFuel] ?? .infinity) } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Fuel", selection: $selectedFuel) { ForEach(FuelType.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu).tint(.mint).padding(.horizontal)
                Toggle(isOn: $showMap) { Label(showMap ? "Map" : "Stations", systemImage: showMap ? "map" : "list.bullet") }.padding(.horizontal)
                Toggle("Price alerts", isOn: $alertsEnabled).tint(.mint).padding(.horizontal)
                if showMap { Map { ForEach(stations) { station in Annotation(station.name, coordinate: station.coordinate.location) { Text(station.prices[selectedFuel].map { String(format:"%.1f¢",$0) } ?? "—").font(.caption.bold()).padding(7).background(.mint,in:Circle()).foregroundStyle(.black) } } }.mapStyle(.standard(elevation:.realistic)).clipShape(RoundedRectangle(cornerRadius:18)).padding() }
                else { List(stations) { station in StationRow(station: station, fuel: selectedFuel) }.listStyle(.plain) }
            }
            .background(Color.black).navigationTitle("CoastFuel").task { await service.load() }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await service.load() } } label: { Image(systemName:"arrow.clockwise") }.tint(.mint) } }
        }.preferredColorScheme(.dark)
    }
}

private struct StationRow: View {
    let station: FuelStation
    let fuel: FuelType
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName:"fuelpump.fill").foregroundStyle(.mint).font(.title2)
            VStack(alignment:.leading,spacing:5) { Text(station.name).font(.headline).foregroundStyle(.white); Text(station.address).font(.caption).foregroundStyle(.secondary); Text("\(station.distanceKm, specifier:"%.1f") km · \(station.amenities.joined(separator:" · "))").font(.caption2).foregroundStyle(.secondary) }
            Spacer(); Text(station.prices[fuel].map { String(format:"%.1f¢",$0) } ?? "—").font(.title3.bold()).foregroundStyle(.mint)
        }.listRowBackground(Color(white:0.07)).padding(.vertical,5)
    }
}
