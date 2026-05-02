import SwiftUI

// MARK: - Water Data Status Enums
enum SnowpackStatus {
    case excellent, average, belowAverage, concerning

    var description: String {
        switch self {
        case .excellent: return "Excellent"
        case .average: return "Average"
        case .belowAverage: return "Below Average"
        case .concerning: return "Concerning"
        }
    }

    var color: Color {
        switch self {
        case .excellent: return .green
        case .average: return .blue
        case .belowAverage: return .orange
        case .concerning: return .red
        }
    }
}

enum PrecipitationStatus {
    case wet, normal, dry, drought

    var description: String {
        switch self {
        case .wet: return "Wet"
        case .normal: return "Normal"
        case .dry: return "Dry"
        case .drought: return "Drought Signal"
        }
    }

    var color: Color {
        switch self {
        case .wet: return .blue
        case .normal: return .green
        case .dry: return .orange
        case .drought: return .red
        }
    }
}

enum ReservoirStatus {
    case strong, healthy, watch, concern

    var description: String {
        switch self {
        case .strong: return "Strong"
        case .healthy: return "Healthy"
        case .watch: return "Watch Level"
        case .concern: return "Concern"
        }
    }

    var color: Color {
        switch self {
        case .strong: return .green
        case .healthy: return .blue
        case .watch: return .orange
        case .concern: return .red
        }
    }
}


// MARK: - WaterData Struct
struct WaterData: Identifiable, Hashable, Equatable {
    let id = UUID()
    let dateString: String
    let monthYear: String
    let snowpack: Double // % of April 1 avg
    let precip: Double   // % of avg
    let reservoir: Double // % capacity
    
    // Normalizes snowpack to dictate the timeline tick height
    var normalizedTickHeight: CGFloat {
        // Visualization height range (8-40pt)
        let height = (snowpack / 150.0) * 36.0 // Assuming max reasonable snowpack for visualization
        return max(8, min(height, 40)) 
    }

    // Computed properties to return status based on defined metrics
    var snowpackStatus: SnowpackStatus {
        if snowpack >= 120 { return .excellent }
        else if snowpack >= 90 { return .average }
        else if snowpack >= 70 { return .belowAverage }
        else { return .concerning }
    }

    var precipitationStatus: PrecipitationStatus {
        if precip >= 110 { return .wet }
        else if precip >= 90 { return .normal }
        else if precip >= 70 { return .dry }
        else { return .drought }
    }

    var reservoirStatus: ReservoirStatus {
        if reservoir >= 85 { return .strong }
        else if reservoir >= 70 { return .healthy }
        else if reservoir >= 50 { return .watch }
        else { return .concern }
    }
}
