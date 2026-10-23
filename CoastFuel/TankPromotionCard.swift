import SwiftUI
import UIKit

struct TankPromotionCard: View {
    private let appURL = URL(string: "tank://")!
    private let appStoreURL = URL(string: "https://apps.apple.com/au/app/tank-fuel-tracker/id6766018177")!

    var body: some View {
        Button(action: openTank) {
            HStack(spacing: 14) {
                Image(systemName: "fuelpump.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.mint)
                    .frame(width: 46, height: 46)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tank - Fuel Tracker")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text("Track every fill-up and fuel cost")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.caption.bold())
                    .foregroundStyle(.mint)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Color.black)
        .accessibilityHint("Opens Tank if installed, otherwise opens its App Store page")
    }

    private func openTank() {
        UIApplication.shared.open(appURL, options: [:]) { opened in
            if !opened {
                UIApplication.shared.open(appStoreURL, options: [:])
            }
        }
    }
}
