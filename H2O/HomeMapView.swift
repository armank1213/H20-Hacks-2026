import SwiftUI
import MapKit

struct HomeMapView: View {
    // 1. Define the bounding region for California
    let californiaRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 36.778259, longitude: -119.417931), // Center of CA
        span: MKCoordinateSpan(latitudeDelta: 9.5, longitudeDelta: 10.0) // Approximate span of CA
    )
    
    var body: some View {
        // 2. Lock the map to California bounds
        Map(bounds: MapCameraBounds(
            centerCoordinateBounds: californiaRegion,
            minimumDistance: 100_000,   // How close the user can zoom in
            maximumDistance: 2_500_000  // How far the user can zoom out
        )) {
            // 3. Apply the grey overlay for everything outside CA
            MapPolygon(createInvertedCaliforniaPolygon())
                .foregroundStyle(.black.opacity(0.6)) // Adjust opacity/color for "greyed out" effect
        }
        .edgesIgnoringSafeArea(.all)
    }
    
    // MARK: - Overlay Generation
    func createInvertedCaliforniaPolygon() -> MKPolygon {
        // Create an outer boundary covering the whole world
        let worldCoords =[
            CLLocationCoordinate2D(latitude: 90, longitude: -180),
            CLLocationCoordinate2D(latitude: 90, longitude: 180),
            CLLocationCoordinate2D(latitude: -90, longitude: 180),
            CLLocationCoordinate2D(latitude: -90, longitude: -180)
        ]
        
        // Coordinates for California's borders
        // NOTE: This is a highly simplified shape so the code runs out-of-the-box.
        let caCoords =[
            CLLocationCoordinate2D(latitude: 42.00, longitude: -124.30), // NW Corner
            CLLocationCoordinate2D(latitude: 42.00, longitude: -120.00), // NE Corner
            CLLocationCoordinate2D(latitude: 39.00, longitude: -120.00), // Tahoe area
            CLLocationCoordinate2D(latitude: 34.26, longitude: -114.13), // Colorado River
            CLLocationCoordinate2D(latitude: 32.72, longitude: -114.73), // SE Corner (Border)
            CLLocationCoordinate2D(latitude: 32.53, longitude: -117.12), // SW Corner (San Diego)
            CLLocationCoordinate2D(latitude: 34.45, longitude: -120.47), // Point Conception
            CLLocationCoordinate2D(latitude: 36.60, longitude: -121.90), // Monterey
            CLLocationCoordinate2D(latitude: 37.80, longitude: -122.50), // San Francisco
            CLLocationCoordinate2D(latitude: 40.44, longitude: -124.40)  // Cape Mendocino
        ]
        
        // Define California as an "Interior Polygon" (a hole cut out of the outer polygon)
        let interiorPolygon = MKPolygon(coordinates: caCoords, count: caCoords.count)
        
        // Return the world polygon with the California hole cut out
        return MKPolygon(coordinates: worldCoords, count: worldCoords.count, interiorPolygons: [interiorPolygon])
    }
}

#Preview {
    HomeMapView()
}