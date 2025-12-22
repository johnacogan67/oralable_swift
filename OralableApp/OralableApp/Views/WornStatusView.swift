//
//  WornStatusView.swift
//  OralableApp
//
//  Created by John A Cogan on 22/12/2025.
//


import SwiftUI

/// An Apple-inspired UI component to indicate sensor coupling and HR.
struct WornStatusView: View {
    let result: HeartRateService.HRResult
    
    var body: some View {
        HStack(spacing: 12) {
            // Pulse Circle
            ZStack {
                Circle()
                    .stroke(result.isWorn ? Color.green.opacity(0.2) : Color.gray.opacity(0.1), lineWidth: 4)
                    .frame(width: 44, height: 44)
                
                if result.isWorn {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                        .scaleEffect(result.isWorn ? 1.1 : 1.0)
                        .animation(Animation.easeInOut(duration: 0.6).repeatForever(), value: result.isWorn)
                } else {
                    Image(systemName: "person.fill.viewfinder")
                        .foregroundColor(.gray)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(result.isWorn ? "Sensor Coupled" : "Reposition Sensor")
                    .font(.custom("OpenSans-Bold", size: 14))
                    .foregroundColor(.primary)
                
                if result.isWorn {
                    Text("\(result.bpm) BPM")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundColor(.secondary)
                } else {
                    Text("Finding pulse at masseter...")
                        .font(.custom("OpenSans-Regular", size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Signal Quality Bar
            HStack(spacing: 2) {
                ForEach(0..<4) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(qualityColor(for: index))
                        .frame(width: 4, height: CGFloat(index + 1) * 4)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
    
    private func qualityColor(for index: Int) -> Color {
        let barsToFill = Int(result.confidence * 4)
        if index < barsToFill {
            return result.isWorn ? .green : .orange
        }
        return Color.gray.opacity(0.2)
    }
}