import Foundation

/// Estimates remaining driving range and recommends affordable stations using the vehicle's profile.
struct FuelRangeAdvisor {
    var tankCapacityLitres: Double = 51
    var averageConsumptionLitresPer100Km: Double = 7
    var lowFuelThresholdPercent: Double = 15

    struct Recommendation {
        let text: String
        let cheapestReachableStation: FuelStation?
        let isLowFuel: Bool
    }

    func estimatedRangeKm(fuelLevelPercentage: Double?) -> Double? {
        guard let percent = fuelLevelPercentage, tankCapacityLitres > 0,
              averageConsumptionLitresPer100Km > 0 else { return nil }
        return tankCapacityLitres * min(max(percent, 0), 100) / 100
            / averageConsumptionLitresPer100Km * 100
    }

    func recommendation(fuelLevelPercentage: Double?, stations: [FuelStation], fuel: FuelType) -> Recommendation {
        let range = estimatedRangeKm(fuelLevelPercentage: fuelLevelPercentage)
        let low = (fuelLevelPercentage ?? 100) <= lowFuelThresholdPercent
        let reachable = stations.filter { range.map { $0 >= $1.distanceKm } ?? false }
        let cheapest = reachable.compactMap { station -> (FuelStation, Double)? in
            guard let price = station.prices[fuel] else { return nil }
            return (station, price)
        }.min { $0.1 < $1.1 }?.0
        let text: String
        if low, let nearest = stations.min(by: { $0.distanceKm < $1.distanceKm }),
           let range, nearest.distanceKm > range {
            text = "Low fuel warning — no listed station is within estimated range."
        } else if low {
            text = "Low fuel warning — refuel soon."
        } else if let cheapest {
            text = String(format: "Cheapest fuel within range: %@ in %.1f km", cheapest.name, cheapest.distanceKm)
        } else if range != nil {
            text = "Good on fuel — no priced station found within estimated range."
        } else {
            text = "Connect to OBD-II to estimate your range."
        }
        return Recommendation(text: text, cheapestReachableStation: cheapest, isLowFuel: low)
    }
}
