#if canImport(CoreGraphics)
import XCTest
import CoreGraphics
@testable import LaTraceMapSDK

final class StaticMapTests: XCTestCase {

    private func queryItems(
        pois: [Poi],
        poiColors: [String: ConfigOverride.PoiColor] = [:],
        poiIcons: [String: String] = [:],
        poiBorderColor: String? = nil,
        poiBorderWidth: Double? = nil
    ) throws -> [String: String?] {
        let request = try XCTUnwrap(laTraceStaticMapRequest(
            configId: "cfg-1",
            apiKey: "pk_live_x",
            apiBaseUrl: URL(string: "https://api.example.app")!,
            center: [2.35, 48.85],
            zoom: 12,
            size: CGSize(width: 300, height: 200),
            pois: pois,
            poiColors: poiColors,
            poiIcons: poiIcons,
            poiBorderColor: poiBorderColor,
            poiBorderWidth: poiBorderWidth
        ))
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
    }

    private func poi(category: String, poiType: String? = nil) -> Poi {
        Poi(id: "p1", coords: [2.35, 48.85], category: category, name: .plain("P"), poiType: poiType)
    }

    func testCategoryKeysMatchTrimmedAndCaseInsensitively() throws {
        let items = try queryItems(
            pois: [poi(category: "restaurant")],
            poiColors: [" Restaurant ": ConfigOverride.PoiColor(background: "#FFFFFF", text: "#E30613")],
            poiIcons: ["Restaurant": "https://cdn.example.app/resto.png"]
        )
        XCTAssertEqual(items["markers"], "2.35,48.85,,E30613-FFFFFF,https://cdn.example.app/resto.png")
    }

    func testPoiTypeIconStaysExactAndWinsOverCategory() throws {
        let icons = [
            "Bistro": "https://cdn.example.app/bistro.png",
            "restaurant": "https://cdn.example.app/resto.png"
        ]
        let exact = try queryItems(pois: [poi(category: "Restaurant", poiType: "Bistro")], poiIcons: icons)
        XCTAssertEqual(exact["markers"], "2.35,48.85,Bistro,,https://cdn.example.app/bistro.png")

        let otherCase = try queryItems(pois: [poi(category: "Restaurant", poiType: "bistro")], poiIcons: icons)
        XCTAssertEqual(otherCase["markers"], "2.35,48.85,bistro,,https://cdn.example.app/resto.png")
    }

    func testBorderColorTravelsAsBareHex() throws {
        let withBorder = try queryItems(pois: [poi(category: "restaurant")], poiBorderColor: "#000000")
        XCTAssertEqual(withBorder["border"], "000000")

        let withoutBorder = try queryItems(pois: [poi(category: "restaurant")])
        XCTAssertNil(withoutBorder["border"])
    }

    func testBorderWidthTravelsOnlyWhenUsable() throws {
        XCTAssertEqual(try queryItems(pois: [], poiBorderWidth: 1)["borderWidth"], "1.0")
        XCTAssertNil(try queryItems(pois: [])["borderWidth"])
        XCTAssertNil(try queryItems(pois: [], poiBorderWidth: -1)["borderWidth"])
        XCTAssertNil(try queryItems(pois: [], poiBorderWidth: .nan)["borderWidth"])
    }
}
#endif
