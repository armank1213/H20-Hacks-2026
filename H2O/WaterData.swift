//
//  WaterData.swift
//  H2O
//
//  Created by Chey K on 5/2/26.
//


import SwiftUI

struct WaterData: Identifiable, Hashable {
    let id = UUID()
    let dateString: String
    let monthYear: String
    let snowpack: Double
    let precip: Double
    let reservoir: Double
    
    // Normalizes precipitation to dictate the timeline tick height
    var normalizedTickHeight: CGFloat {
        let height = (precip / 150.0) * 36.0
        return max(4, height) 
    }
}