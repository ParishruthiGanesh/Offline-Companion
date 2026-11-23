# Attribution

Built with Llama.

The model is Meta Llama 3.2 1B Instruct. Model weights are not included in this source archive. Review and comply with the Llama 3.2 Community License and Acceptable Use Policy before downloading, using, or distributing weights:
- https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct/blob/main/LICENSE.txt
- https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct/blob/main/USE_POLICY.md

GGUF conversion/quantization supplied by bartowski:
https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF

LlamaSwift (MIT): https://github.com/mattt/llama.swift
llama.cpp (MIT): https://github.com/ggml-org/llama.cpp

These libraries are fetched as dependencies during Xcode setup; their respective license notices remain in their distributions. New application source in this archive is not copied from their example applications.

Photo mode adds SmolVLM-500M-Instruct by HuggingFaceTB (Hugging Face), with GGUF conversion from ggml-org. It is not a Meta model. Weights are downloaded separately and are not bundled in this archive. Review the current model card and license before use/distribution:
- https://huggingface.co/HuggingFaceTB/SmolVLM-500M-Instruct
- https://huggingface.co/ggml-org/SmolVLM-500M-Instruct-GGUF


## New map data and platform frameworks
Country boundaries and selected major cities are derived from Natural Earth 1:110m data (public domain): https://www.naturalearthdata.com/about/terms-of-use/ . Source GeoJSON: https://github.com/nvkelso/natural-earth-vector . Countries.geojson preserves exterior country polygons; Cities.json contains selected capital/major-city points. These are coarse overview data, not detailed navigation maps.

Regional roads, paths and waterways downloaded by the app are OpenStreetMap data under ODbL, credited in the map UI: https://www.openstreetmap.org/copyright . The public Overpass endpoints are https://overpass-api.de/api/interpreter and https://overpass.private.coffee/api/interpreter . Requests are user initiated, sequential, limited to a 1–5 km local radius and capped at 12 MB per response. A production launch needs appropriate hosted capacity; no full-country bulk-download permission or service guarantee is implied.

The renderer uses MapLibre Native iOS 7.0.0, distributed through https://github.com/maplibre/maplibre-gl-native-distribution . Its BSD licence is included at DeveloperNotes/MapLibre-LICENSE.md. Package integrity is verified by Swift Package Manager. The former Canvas renderer and MultipeerConnectivity transport have been removed from the application target.

Latin Noto Sans Regular glyphs are bundled from https://github.com/maplibre/demotiles/tree/gh-pages/font . Noto Sans is distributed under the SIL Open Font License, included in MapGlyphs/OFL.txt and DeveloperNotes/NotoSans-OFL.txt. Only the 0–255 glyph range is bundled; unsupported scripts may have missing map labels. These glyphs and all style sources are local—no online basemap fallback is used.

Stored regional JSON is compressed with Apple's LZFSE API. Bluetooth uses Apple's Core Bluetooth, CryptoKit and Keychain frameworks. No Google Maps, Mapbox service or OpenFreeMap data is incorporated. No map API key is required for this prototype. Walking-route preview logic is application code using downloaded OSM connectivity/access information; it is not a production routing service.

## Bundled Auburn OpenStreetMap database
AuburnMap.json is an openly supplied adapted database derived from OpenStreetMap contributors via the Geofabrik Alabama extract: https://download.geofabrik.de/north-america/us/alabama.html . The adapted database is licensed under the Open Data Commons Open Database License 1.0 (ODbL): https://opendatacommons.org/licenses/odbl/1-0/ . Attribution and source: https://www.openstreetmap.org/copyright . The complete adapted database is included in this ZIP in editable JSON form; it may be extracted and reused under ODbL. No new restrictions are placed on that database. Application code and third-party libraries retain their separate licenses.
The extract was retrieved on 2026-11-04. Only roads, paths, waterways, names and relevant walking/access/connectivity attributes are retained within the Auburn-area rectangle. No complete-city or live-condition guarantee is made. See DeveloperNotes/AUBURN_DATA.md for processing and validation details.
