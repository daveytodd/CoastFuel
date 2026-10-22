import Foundation

/// Estimates remaining driving range and recommends reachable fuel stations.
struct FuelRangeAdvisor {
    var tankCapacityLitres: Double = 51
    var consumptionLitresPer100Km: Double = 7
    var criticalRangeKm: Double = 50

    struct Recommendation {
        let rangeKm: Double
        let text: String
        let cheapestStation: FuelStation?
    }

    func estimatedRange(fuelLevelPercentage: Double?) -> Double? {
        guard let percentage = fuelLevelPercentage else { return nil }
        let bounded = min(max(percentage, 0), 100)
        return tankCapacityLitres * bounded / 100 / consumptionLitresPer100Km * 100
    }

    func recommendation(fuelLevelPercentage: Double?, stations: [FuelStation], fuel: FuelType) -> Recommendation? {
        guard let range = estimatedRange(fuelLevelPercentage: fuelLevelPercentage) else { return nil }
        let reachable = stations.filter { $0.distanceKm <= range }
        let cheapest = reachable.compactMap { station -> (FuelStation, Double)? in
            guard let price = station.prices[fuel] else { return nil }
            return (station, price)
        }.min { $0.1 < $1.1 }?.0
        let text: String
        if range <= criticalRangeKm {
            text = cheapest.map { String(format: "Low fuel warning — %@ is %.1f km away; refuel now.", $0.name, $0.distanceKm) } ?? "Low fuel warning — no priced station is within estimated range."
        } else if let cheapest {
            text = String(format: "Cheapest fuel within range: %@ in %.1f km.", cheapest.name, cheapest.distanceKm)
        } else {
            text = "Good on fuel — no priced station found within estimated range."
        }
        return Recommendation(rangeKm: range, text: text, cheapestStation: cheapest)
    }
}
