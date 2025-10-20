//
//  StoaAIWidgetBundle.swift
//  StoaAIWidget
//
//  Created by Ahmet Kemal  Akbudak on 19.07.2025.
//

import WidgetKit
import SwiftUI

@main
struct StoaAIWidgetBundle: WidgetBundle {
    var body: some Widget {
        StoaAIWidget()
        StoaAIWidgetControl()
        StoaAIWidgetLiveActivity()
    }
}
