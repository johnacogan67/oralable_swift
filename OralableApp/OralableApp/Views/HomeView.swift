//
//  HomeView.swift
//  OralableApp
//
//  Primary home tab: Apple Health–style Summary (TFI + hypoxic burden) lives in `DashboardView`
//  (`showAppleHealthSummary`); metric cards and recording flow follow below.
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        DashboardView(
            suppressTemporalisSummary: true,
            showAppleHealthSummary: true
        )
    }
}
