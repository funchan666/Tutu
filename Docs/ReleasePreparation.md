# Tutu release preparation

This pass used source, configuration, resource-reference and file-integrity inspection. No app compilation, type checking, tests, simulator/device run, archive, upload or purchase was performed.

## Cleanup

Removed obsolete screenshots and contact sheets, image-generation prompt files, five outdated design/implementation review documents, Finder state and Xcode per-user workspace state. Removed six unused legacy image sets: icon-flame, live-banner, voice-banner, style-minimalist, style-streetwear and style-vintage. The asset-import exclusion list and asset mapping were updated so a later import does not reintroduce them.

The original supplied design directory remains outside the application target. Backend source snapshots are inputs to the content exporter and were preserved. The font license, artwork provenance, privacy manifest, signing team, Bundle ID, registered URL scheme and authentication/payment contracts remain intact. Git history was not rewritten or deleted; it is not included in the app resource phase.

No local home-folder paths, machine names or developer login identifiers were found in the scanned application source, configuration and maintained text files. No Docs, Scripts, supplied source directory, generation output, local StoreKit configuration or per-user Xcode state is included in Copy Bundle Resources. Xcode can recreate ignored per-user state while open; those files remain excluded from source control and app resources. This cleanup does not guarantee an App Review decision or eliminate legitimate developer-account association.

## Size and image integrity

Current application source resources: 32,320,498 bytes, or 32.32 MB / 30.82 MiB. This excludes the compiled executable, linked frameworks, compiled asset-catalog changes, signing and App Store thinning/compression. There is no current IPA size measurement. The final download/install size cannot be confirmed below 50 MB without an authorized archive and size report.

Lossless PNG optimization saved 5,330,609 bytes, approximately 5.08 MiB. All 81 processed PNGs retained the same dimensions and decoded RGBA pixels; display metadata was checked unchanged. Six of those PNGs belonged to unused sets subsequently removed. Fifteen signed artwork files were preserved byte-for-byte, including their provenance metadata. No downscaling, color quantization, JPEG conversion or alpha-pixel modification was used.

Removed intermediate files, user state and unused image sets total 29,482,466 bytes. Most intermediates were already outside the app target, so that whole amount is not an IPA reduction.

Release settings now explicitly enable COPY_PHASE_STRIP, STRIP_INSTALLED_PRODUCT and STRIP_SWIFT_SYMBOLS, disable testability and retain debug information in an external dSYM. Keep dSYMs for crash diagnosis; do not add them to application resources. Existing Release optimization and whole-module compilation remain unchanged.

## StoreKit evidence

There is no .storekit file, SKTestSession integration or StoreKitConfigurationFileReference in the project. WalletService requests Apple Product records, requires a consumable product, calls Product.purchase, accepts verified transactions and persists delivery before finishing. User cancellation, pending approval and errors do not fabricate purchased coins. Initial rewards and check-in rewards are distinct from purchase grants.

The nine current product IDs, coin quantities and reference USD amounts match IAPProducts.csv and the backend content response. Names and descriptions comply with the documented 30/45 character limits. Prices in this sheet are configuration values; actual App Store Connect configuration and storefront prices have not been verified.

App Review uses Apple's sandbox for In-App Purchase evaluation. That is expected and is different from Xcode-local simulated transactions. Reviewers must be able to fetch the submitted Apple products and complete the purchase flow. Before submission, confirm the nine consumables, their availability/prices, agreements and payment prerequisites in App Store Connect, include the relevant purchases with the submission, and verify StoreKit sandbox purchase and both local/server delivery paths. Server receipt handling must support the official sandbox appropriately. No successful live or sandbox transaction is claimed by this source inspection.

## Actual feature and account boundaries

The source currently keeps private-message delivery unavailable. Calls have real permission requests and a local camera preview, but no remote RTC session. Current room activity includes authored local presentation content. Style advice uses a device language model when supported and curated text guidance otherwise, without image analysis. ASO copy reflects these limits rather than presenting connected services as completed features.

No active review account was found or created. Backend login requires a genuinely provisioned account that works from a separate device; local credentials or invented examples are not a substitute. A dedicated review account is still required. Do not commit its password.

The terms and privacy URLs returned HTTPS 200 with Tutu titles. Their substantive disclosures and App Store privacy answers still need to match actual backend data collection and retention; HTTP availability alone does not establish that match. No changes to privacy declarations were made by guessing server behavior.

## Completed checks

All asset-catalog filenames resolve. All 86 CDN media mappings and legacy aliases remain consistent. The frozen backend contract, source data, 24 room records, 30 comments, 9 products and exported templates pass the existing offline reference audit. Source file target membership, Release settings and excluded maintenance files were inspected. git diff --check passes. No product purchase, backend login, server settlement or review-account login was executed.

## Apple references

https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases
https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information/
https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/
https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/
