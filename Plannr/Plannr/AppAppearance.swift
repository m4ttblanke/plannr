//
//  AppAppearance.swift
//  Plannr
//
//  One-time UIKit appearance setup for controls SwiftUI can't fully style on
//  its own. Called once from PlannrApp.init so it isn't re-applied lazily from
//  a view's .onAppear (which mutates shared UIKit state on every appearance).
//

import UIKit

enum AppAppearance {
    static func configure() {
        let segmented = UISegmentedControl.appearance()
        segmented.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        segmented.setTitleTextAttributes([.foregroundColor: UIColor.darkGray], for: .selected)
        segmented.backgroundColor = UIColor.darkGray
    }
}
