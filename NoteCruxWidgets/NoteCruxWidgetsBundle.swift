//
//  NoteCruxWidgetsBundle.swift
//  NoteCruxWidgets
//
//  Created by Bistro Kaspar on 4/20/26.
//

import WidgetKit
import SwiftUI

@main
struct NoteCruxWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NoteCruxWidgets()
        NoteCruxWidgetsControl()
        NoteCruxWidgetsLiveActivity()
    }
}
