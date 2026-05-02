import SwiftUI
import MapKit

struct HomeMapView: View {
    // 1. Coordinates for Fresno, California
    let fresnoCoordinate = CLLocationCoordinate2D(latitude: 36.7468, longitude: -119.7726)
    
    // 2. Define the bounding region centered on Fresno
    // (This dictates how far away from Fresno the user is allowed to pan)
    var panningBounds: MKCoordinateRegion {
        MKCoordinateRegion(
            center: fresnoCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0) // Keeps panning locked to California
        )
    }
    
    var body: some View {
        Map(
            // 3. Start the map looking directly at Fresno
            initialPosition: .camera(
                MapCamera(
                    centerCoordinate: fresnoCoordinate,
                    distance: 1_500_000 // Adjust this to start closer in or further out
                )
            ),
            // 4. Set the panning and zoom limits
            bounds: MapCameraBounds(
                centerCoordinateBounds: panningBounds,
                minimumDistance: 4_000_000,   // Allows zooming in close to Fresno streets
                maximumDistance: 5_000_000 // Allows zooming out to see the whole state
            )
        )
        .edgesIgnoringSafeArea(.all)
    }
}

#Preview {
    HomeMapView()
}
