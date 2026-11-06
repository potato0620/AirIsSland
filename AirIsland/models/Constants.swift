//
//  Constants.swift
//  AirIsland
//
//  Created by Richard Kunkli on 2024. 10. 17..
//

import SwiftUI
import Defaults

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

extension Defaults.Keys {
    // MARK: General
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: false)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    
    // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.2)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let showPageIndicators = Key<Bool>("showPageIndicators", default: true)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let nonNotchWidthPercentage = Key<CGFloat>("nonNotchWidthPercentage", default: NonNotchWidth.defaultPercentage)
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    static let showOnLockScreen = Key<Bool>("showOnLockScreen", default: false)
    static let hideFromScreenRecording = Key<Bool>("hideFromScreenRecording", default: false)
    
    // MARK: Appearance
    static let lightingEffect = Key<Bool>("lightingEffect", default: true)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let cornerRadiusScaling = Key<Bool>("cornerRadiusScaling", default: true)

    static let sliderColor = Key<SliderColorEnum>(
        "sliderUseAlbumArtColor",
        default: SliderColorEnum.white
    )
    
    // MARK: Media playback
    static let musicLiveActivityEnabled = Key<Bool>("musicLiveActivityEnabled", default: true)
    static let enableSneakPeek = Key<Bool>("enableSneakPeek", default: true)
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    static let timerActivityEnabled = Key<Bool>("timerActivityEnabled", default: true)
    static let remindersActivityEnabled = Key<Bool>("remindersActivityEnabled", default: true)
    static let reminderListIdentifier = Key<String>("reminderListIdentifier", default: "")
    // MARK: Battery
    static let showPowerStatusNotifications = Key<Bool>("showPowerStatusNotifications", default: true)

    // MARK: HUD
    static let hudReplacement = Key<Bool>("hudReplacement", default: false)
    
    // MARK: Fullscreen Media Detection
    static let hideNotchOption = Key<HideNotchOption>("hideNotchOption", default: .nowPlayingOnly)
    
}
