//
//  AppColors.swift
//  Plannr
//
//  Shared colors. `secondaryText` replaces bare `.gray` for captions / hints on
//  the app's dark backgrounds — plain `Color.gray` (~0.56 white) sits around
//  3.4:1 on black, under the WCAG AA 4.5:1 bar; this is ~4.8:1.
//

import SwiftUI

extension Color {
    static let secondaryText = Color(white: 0.72)
}
