//
//  ContentActionable.swift
//  SlideController_Example
//
//  Created by Pavel Kondrashkov on 10/24/17.
//  Copyright © 2017 Touchlane LLC. All rights reserved.
//

protocol ContentActionable {
    typealias Action = () -> Void
    
    var removeDidTapAction: Action? { get set }
    var insertDidTapAction: Action? { get set }
    var appendDidTapAction: Action? { get set }
    var menuDidTapAction: Action? { get set }
}
