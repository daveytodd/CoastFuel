# CoastFuel

CoastFuel is an iOS 17+ SwiftUI app concept for finding Queensland / Gold Coast fuel stations, comparing prices, and browsing stations in CarPlay. The app includes realistic fallback fixtures so it runs without API credentials.

## Open in Xcode

This repository uses XcodeGen. Install XcodeGen (`brew install xcodegen`), clone the repository, run `xcodegen generate` in the repository root, then open `CoastFuel.xcodeproj` in Xcode. Select an iOS 17+ simulator and run. Alternatively open `project.yml` in an XcodeGen-capable workflow.

To test CarPlay, run the app on a supported simulator, then use Xcode's I/O > External Displays > CarPlay (menu wording may vary by Xcode version). CarPlay availability and entitlement behavior depend on Apple's simulator and provisioning support.

## CarPlay entitlement

Fueling apps require Apple's CarPlay fueling entitlement (`com.apple.developer.carplay-fueling`). Apply through the Apple Developer program and do not expect CarPlay fueling scenes to be available until Apple approves and provisions the entitlement. Add the entitlement to the signed app only after approval. This sample includes the scene configuration but does not claim entitlement approval.

## Fuel data

`FuelDataService` attempts the Queensland Open Data fuel-price API endpoint and gracefully falls back to included Gold Coast fixture data on network, decoding, or schema errors. The government API schema and access policy can change; adjust the adapter if needed. Fixture prices are illustrative, not live prices.

## Notes

- Bundle identifier: `com.daveytodd.CoastFuel`
- Deployment target: iOS 17.0
- SwiftUI phone UI with station list, map, fuel filter, and local price-alert controls.
- CarPlay list and point-of-interest templates with station prices and Apple Maps directions.
- Do not interact with the app while driving; CarPlay UI is intentionally glanceable.
