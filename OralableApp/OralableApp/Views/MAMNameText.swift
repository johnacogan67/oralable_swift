//
//  MAMNameText.swift
//  MAMDiagnostics
//
//  Product name with the A in brand red. Use for the logo and short titles.
//  Leave the A black inside sentences, file names, and the Bluetooth name.
//

import SwiftUI

enum MAMBrand {
    /// Same red as the pulse on the app icon.
    static let red = Color(red: 200.0 / 255.0, green: 16.0 / 255.0, blue: 46.0 / 255.0)
}

struct MAMNameText: View {
    var prefix: String = ""
    var suffix: String = ""

    var body: some View {
        (Text(prefix) + Text("M") + Text("A").foregroundColor(MAMBrand.red) + Text("M") + Text(suffix))
            .accessibilityLabel(prefix + "MAM" + suffix)
    }
}
