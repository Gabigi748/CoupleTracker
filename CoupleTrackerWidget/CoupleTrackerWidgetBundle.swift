// CoupleTrackerWidgetBundle.swift
// CoupleTrackerWidget
//
// Widget Extension 入口 — 包含 Live Activity 配置
// 注意：此檔案屬於 Widget Extension target

import WidgetKit
import SwiftUI

@main
struct CoupleTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        CoupleTrackerLiveActivity()
    }
}
