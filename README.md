# Tutu

Native SwiftUI iPhone app for outfit inspiration, curated fashion videos and personal style collections. Minimum deployment target: iOS 17. Open `Tutu.xcodeproj` with scheme `Tutu`; `project.yml` is the XcodeGen source.

The current Bundle ID is `com.tutustyleoutfit.lookbook`. Keep the registered application, signing capabilities, URL scheme and App Store Connect products consistent with that identity. Release configuration retains debug symbols in the separate dSYM and enables standard symbol stripping. A dSYM is useful for crash diagnosis and is not an application resource.

## Content and current functionality

Content metadata is delivered by the configured backend. The 74 supplied photos and 12 supplied videos use HTTPS CDN URLs. Twelve video posters and the original interface artwork remain bundled. Local profile edits, likes, comments, follows, moderation preferences, style history, wardrobe entries, coin balance and collectibles persist on the device.

Style advice uses the on-device language model on supported devices, with curated text guidance otherwise. Photos are visual references, not inputs to image recognition. Five initial replies are free; subsequent completed replies cost 20 coins.

Current room activity includes authored local messages and gift effects. Private-message sending is unavailable, and call screens provide permission handling and local camera preview without a remote RTC connection. Do not describe these as verified real-time social services. Backend login, realtime delivery and payment settlement remain subject to integration verification.

## Purchases and submission

Purchases use Apple StoreKit products, Apple's payment sheet and verified transactions. No `.storekit` file or Xcode simulated-purchase configuration is included. Product availability and pricing must be configured in App Store Connect. A transaction is finished only after the corresponding durable delivery state is recorded. Sandbox purchase and backend settlement have not been verified for this revision.

- [App Store copy and current review-account status](Docs/AppStoreMetadata.md)
- [In-App Purchase fields and reference USD prices](Docs/IAPProducts.csv)
- [Release cleanup and resource-size evidence](Docs/ReleasePreparation.md)
- [Backend contract and deployment handoff](Docs/BackendAPI/README.md)
- [Artwork provenance](Docs/AssetProvenance.md)

## Maintenance

`python3 Scripts/import_content.py` maintains CDN references and legacy aliases without downloading media. `python3 Docs/BackendAPI/export_content.py` regenerates content responses from the preserved source records. Regenerate deployment templates using the frozen backend contract. `python3 Docs/BackendAPI/audit_delivery.py` performs offline data and resource checks; it is not an app build or runtime verification.

The `sucai` directory retains supplied source designs outside the application target. Backend source snapshots are required by the exporter and must not be deleted as unused text. Keep the font license and privacy manifest. Old screenshots, generator prompts and obsolete review notes have been removed. None of these maintenance directories are application resources.
