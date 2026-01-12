//
//  RootView.swift
//  OralableApp
//
//  Root view wrapper that displays the main DashboardView.
//
//  Purpose:
//  Provides a simple entry point for SwiftUI previews
//  and testing without the full app navigation stack.
//

import SwiftUI

public struct RootView: View {
    public var body: some View {
        DashboardView()
    }
}
