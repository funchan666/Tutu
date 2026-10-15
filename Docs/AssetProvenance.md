# Tutu artwork provenance

The supplied interface designs are preserved in `sucai`, outside the application bundle. `AssetMapping.json` records their semantic Asset Catalog names and whether they are bundled. Source designs are kept for maintenance; they are not copied wholesale into the target.

Eight original stylist images were generated specifically for Tutu: Minimalist, Streetwear, Vintage, Soft Tailoring, Smart Casual, Cozy, City Chic and Weekend. These depict fictional adult models and do not reuse supplied photographs. They remain at their original dimensions under the corresponding `stylist-` image sets.

Other original project artwork includes the wardrobe illustration, welcome wardrobe, party background, runway frame, live signal and voice/video call icons. Signed artwork provenance chunks are preserved. Temporary prompts and rendered review screenshots are no longer retained in this checkout.

The 74 supplied photographs and 12 supplied videos are loaded from the user-provided HTTPS CDN. `ContentMapping.json` retains original filenames, SHA256 values, editorial IDs and remote URLs. Twelve locally derived video posters remain bundled because no remote poster URLs were supplied. Character names and demographics are authored application roles, not biographical claims about the depicted people.

Release optimization uses lossless PNG recompression only. Processed images are checked for identical decoded RGBA pixels, dimensions and display metadata. No downscaling, palette quantization or lossy JPEG conversion is used. Images with signed provenance remain byte-for-byte unchanged. Six unreferenced legacy image sets were removed; current original stylist artwork, active/inactive tabs, dynamically named gifts and all referenced assets remain.

The Outfit font license remains at `Tutu/Resources/Fonts/Outfit-OFL.txt`. Do not remove required license or privacy disclosures as development artifacts.
