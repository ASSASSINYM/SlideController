//
//  ScrollController.swift
//  SlideController
//
//  Created by Evgeny Dedovets on 5/6/17.
//  Copyright © 2017 Touchlane LLC. All rights reserved.
//

import UIKit

public protocol SlidePageLifeCycle: class {
    func didAppear()
    func didDissapear()
    func viewDidLoad()
    func viewDidUnload()
    func didStartSliding()
    func didCancelSliding()
    var isKeyboardResponsive: Bool { get }
}

public protocol Viewable: class {
    var view: UIView { get }
}

public protocol ItemViewable: class {
    associatedtype Item: UIView
    var view: Item { get }
}

public protocol Initializable: class {
    init()
}

public protocol ViewSlidable: class {
    associatedtype View: UIView
    func appendViews(views: [View])
    func insertView(view: View, index: Int)
    func removeViewAtIndex(index: Int)
    var firstLayoutAction: (() -> Void)? { get set }
    var changeLayoutAction: (() -> Void)? { get set }
    var isLayouted: Bool { get }
}

public protocol ControllerSlidable: class {
    func shift(pageIndex: Int, animated: Bool)
    func showNext(animated: Bool)
    func viewDidAppear()
    func viewDidDisappear()
    func insert(object: SlideLifeCycleObjectProvidable, index: Int)
    func append(object: [SlideLifeCycleObjectProvidable])
    func removeAtIndex(index : Int)
}

public protocol Selectable: class {
    var isSelected: Bool { get set }
    var didSelectAction: ((Int) -> Void)? { get set }
    var index: Int { get set }
}

public enum SlideDirection {
    case vertical
    case horizontal
}

public enum TitleViewAlignment {
    case top
    case left
    case right
}

public enum TitleViewPosition {
    case beside
    case above
}

private enum ScrollingDirection {
    case right
    case left
    case up
    case down
}

public typealias TitleItemObject = Selectable & ItemViewable
public typealias TitleItemControllableObject = ItemViewable & Initializable & Selectable
public typealias SlideLifeCycleObject = SlidePageLifeCycle & Viewable & Initializable

public class SlideController<T, N>: NSObject, UIScrollViewDelegate, ControllerSlidable, Viewable where T: ViewSlidable, T: UIScrollView, T: TitleConfigurable, N: TitleItemControllableObject, N: UIView, N.Item == T.View {
    private let containerView = SlideView<T>()
    private var titleSlidableController: TitleSlidableController<T, N>!
    private var slideDirection: SlideDirection!
    private var contentSlidableController: SlideContentController!
    private var currentIndex = 0
    
    private var sourceIndex: Int? = nil
    private var destinationIndex: Int? = nil
    
    private var lastContentOffset: CGFloat = 0
    private var didFinishForceSlide: (() -> ())?
    private var didFinishSlideAction: (() -> Void)?
    private var isForcedToSlide = false
    private var isOnScreen = false
    
    /// Used for disabling scrollViewDidScroll calls when changeContentLayoutAction is triggered
    private var isLayouting = false
    
    /// Indicates if the scroll in progress.
    /// Used for lifecycle.
    /// Used for setting title item selection.
    private var scrollInProgress = false {
        didSet {
            if oldValue != scrollInProgress {
                /// Disable selection and scrolling of title view
                titleSlidableController.isSelectionAllowed = !scrollInProgress
                titleSlidableController.titleView.isScrollEnabled = !scrollInProgress
                /// Once scrolling is started to show title that out of the screen
                if scrollInProgress && !isForcedToSlide {
                    titleSlidableController.jump(index: currentIndex, animated: false)
                }
            }
        }
    }
    
    ///Returns title view instanse of specified type
    public var titleView: T {
        return titleSlidableController.titleView
    }
    
    ///Returns model for access to current LifeCycle object
    public var currentModel: SlideLifeCycleObjectProvidable? {
        if content.indices.contains(currentIndex) {
            return content[currentIndex]
        }
        return nil
    }
    
    ///Array of specified models
    public fileprivate(set) var content = [SlideLifeCycleObjectProvidable]()

    //TODO: Refactoring. we had to add the flag to prevent crash when the current page is being removed
    fileprivate var shouldRemoveContentAfterAnimation: Bool = false
    fileprivate var indexToRemove: Int?
    
    private lazy var firstLayoutTitleAction: () -> () = { [weak self] in
        guard let strongSelf = self else { return }
        strongSelf.changeContentLayoutAction()
    }
    
    private lazy var firstLayoutContentAction: () -> () = { [weak self] in
        guard let strongSelf = self else { return }
        strongSelf.contentSlidableController.slideContentView.delegate = self
    }
    
    private lazy var changeTitleLayoutAction: () -> () = { [weak self] in
        guard let strongSelf = self else { return }
        strongSelf.titleSlidableController.jump(index: strongSelf.currentIndex, animated: false)
    }
    
    private lazy var changeContentLayoutAction: () -> () = { [weak self] in
        guard let strongSelf = self else { return }
        guard !strongSelf.isForcedToSlide else { return }
        strongSelf.isLayouting = true
        strongSelf.contentSlidableController.slideContentView.delegate = nil
        strongSelf.contentSlidableController.contentSize = strongSelf.calculateContentPageSize(
            direction: strongSelf.slideDirection,
            titleViewAlignment: strongSelf.titleSlidableController.titleView.alignment,
            titleViewPosition: strongSelf.titleSlidableController.titleView.position,
            titleSize: strongSelf.titleSlidableController.titleView.titleSize)
        strongSelf.scrollToPage(pageIndex: strongSelf.currentIndex, animated: false)
        strongSelf.contentSlidableController.slideContentView.delegate = strongSelf
        strongSelf.titleSlidableController.isSelectionAllowed = true
        strongSelf.titleSlidableController.titleView.isScrollEnabled = true
    }
    
    private lazy var didSelectItemAction: (Int, (() -> ())?) -> () = { [weak self] (index, completion) in
        guard let strongSelf = self else { return }
        strongSelf.shift(pageIndex: index)
        strongSelf.didFinishForceSlide = completion
    }

    public init(pagesContent: [SlideLifeCycleObjectProvidable], startPageIndex: Int = 0, slideDirection: SlideDirection) {
        super.init()
        content = pagesContent
        self.slideDirection = slideDirection
        titleSlidableController = TitleSlidableController(pagesCount: content.count, slideDirection: slideDirection)
        currentIndex = startPageIndex
        contentSlidableController = SlideContentController(pagesCount: content.count, slideDirection: slideDirection)
        titleSlidableController.didSelectItemAction = didSelectItemAction
        loadView(pageIndex: currentIndex)
        containerView.contentView = contentSlidableController.slideContentView
        containerView.titleView = titleSlidableController.titleView
        titleSlidableController.titleView.firstLayoutAction = firstLayoutTitleAction
        contentSlidableController.slideContentView.firstLayoutAction = firstLayoutContentAction
        titleSlidableController.titleView.changeLayoutAction = changeTitleLayoutAction
        contentSlidableController.slideContentView.changeLayoutAction = changeContentLayoutAction
    }
    
    var isScrollEnabled: Bool = true {
        didSet {
            contentSlidableController.slideContentView.isScrollEnabled = isScrollEnabled
        }
    }

    // MARK: - ControllerSlidableImplementation
    
    public func append(object objects: [SlideLifeCycleObjectProvidable]) {
        guard objects.count > 0 else {
            return
        }
        let shoudLoadView = content.isEmpty
        content.append(contentsOf: objects)
        contentSlidableController.append(pagesCount: objects.count)
        titleSlidableController.append(pagesCount: objects.count)
        
        if shoudLoadView {
            loadView(pageIndex: currentIndex)
        }
        
        if contentSlidableController.slideContentView.isLayouted {
            contentSlidableController.slideContentView.layoutIfNeeded()
        }
        if titleSlidableController.titleView.isLayouted {
            titleSlidableController.titleView.layoutIfNeeded()
        }
        titleSlidableController.jump(index: currentIndex, animated: false)
        
        // Load next view if we were at the last position
        if currentIndex == content.count - 2 {
            loadViewIfNeeded(pageIndex: currentIndex + 1)
        }
    }

    public func insert(object: SlideLifeCycleObjectProvidable, index: Int) {
        guard index < content.count else {
            return
        }
        content.insert(object, at: index)
        contentSlidableController.insert(index: index)
        titleSlidableController.insert(index: index)
        if contentSlidableController.slideContentView.isLayouted {
           contentSlidableController.slideContentView.layoutIfNeeded()
        }
        if titleSlidableController.titleView.isLayouted {
            titleSlidableController.titleView.layoutIfNeeded()
        }
        if index <= currentIndex {
            contentSlidableController.slideContentView.delegate = nil
            let newCurrentIndex = currentIndex + 1
            if self.contentSlidableController.slideContentView.isLayouted {
               shift(pageIndex: newCurrentIndex, animated: false)
            }
            currentIndex = newCurrentIndex
            isForcedToSlide = false
            contentSlidableController.slideContentView.delegate = self
            // Load view if it's around current
            if currentIndex - index <= 1 {
                loadViewIfNeeded(pageIndex: index)
            }
            if index != currentIndex {
                unloadView(at: index - 1)
            }
        } else if index - currentIndex == 1 {
            loadViewIfNeeded(pageIndex: index)
            unloadView(at: index + 1)
        }
    }
    
    public func removeAtIndex(index: Int) {
        guard index < content.count else {
            return
            
        }
        contentSlidableController.slideContentView.delegate = nil
        
        if index == currentIndex && content.indices.contains(index) {
            content[index].lifeCycleObject.didDissapear()
        }
        unloadView(at: index)
        
        content.remove(at: index)
        contentSlidableController.removeAtIndex(index: index)
        titleSlidableController.removeAtIndex(index: index)
        
        let isNearCurrentIndex = currentIndex + 1 == index || currentIndex - 1 == index
        if isNearCurrentIndex || currentIndex == index {
            loadViewIfNeeded(pageIndex: index + 1)
            loadViewIfNeeded(pageIndex: index)
            loadViewIfNeeded(pageIndex: index - 1)
        }
        
        if index < currentIndex {
            shift(pageIndex: currentIndex - 1, animated: false)
            currentIndex = currentIndex - 1
        } else if index == currentIndex {
            /// TODO: check this case
            if currentIndex < content.count {
                shift(pageIndex: currentIndex, animated: false)
            } else {
                shift(pageIndex: currentIndex - 1, animated: false)
                if currentIndex != 0 {
                    currentIndex = currentIndex - 1
                }
            }
        }
        contentSlidableController.slideContentView.delegate = self
    }
    
    public func shift(pageIndex: Int, animated: Bool = true) {
        guard pageIndex != currentIndex else {
            return
        }
        if animated {
            isForcedToSlide = true
        }
        loadViewIfNeeded(pageIndex: pageIndex)
        
        if animated {
            sourceIndex = currentIndex
            destinationIndex = pageIndex
            if content.indices.contains(currentIndex) {
                content[currentIndex].lifeCycleObject.didStartSliding()
                scrollInProgress = true
            }
        } else {
            sourceIndex = nil
            destinationIndex = nil
        }
        
        if !self.contentSlidableController.slideContentView.isLayouted {
            loadViewIfNeeded(pageIndex: pageIndex, truePage: true)
        } else {
            scrollToPage(pageIndex: pageIndex, animated: animated)
        }
    }
    
    public func showNext(animated: Bool = true) {
        var page = currentIndex + 1
        var animated = animated
        if page >= content.count {
            page = 0
            animated = false
        }
        shift(pageIndex: page, animated: animated)
    }
    
    public func viewDidAppear() {
        isOnScreen = true
        if content.indices.contains(currentIndex) {
            content[currentIndex].lifeCycleObject.didAppear()
        }
    }
    
    public func viewDidDisappear() {
        isOnScreen = false
        if content.indices.contains(currentIndex) {
            content[currentIndex].lifeCycleObject.didDissapear()
        }
    }
    
    // MARK: - UIScrollViewDelegateImplementation
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isLayouting else {
            isLayouting = false
            return
        }
        let pageSize = contentSlidableController.contentSize
        let actualContentOffset = slideDirection == .horizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y
        let nextIndex = Int(actualContentOffset / pageSize)

        let isDestinationTransition = nextIndex == (destinationIndex ?? nextIndex)
        let objectIndex = sourceIndex ?? currentIndex
        if !scrollInProgress && !isForcedToSlide && isDestinationTransition {
            if content.indices.contains(objectIndex) {
                content[objectIndex].lifeCycleObject.didStartSliding()
                scrollInProgress = true
            }
        }

        let scrollingDirection = determineScrollingDirection(lastContentOffset: lastContentOffset, currentContentOffset: scrollView.contentOffset)
        if !isForcedToSlide {
            switch scrollingDirection {
            case .up, .right:
                loadViewIfNeeded(pageIndex: nextIndex - 1)
            case .down, .left:
                loadViewIfNeeded(pageIndex: nextIndex + 1)
            }
        }
        
        let didReachContentEdge = actualContentOffset.truncatingRemainder(dividingBy: pageSize) == 0.0
        if didReachContentEdge {
            scrollInProgress = false
            if nextIndex != currentIndex {
                if isDestinationTransition {
                    loadView(pageIndex: nextIndex)
                }
                if !isForcedToSlide {
                    unloadView(around: currentIndex)
                    titleSlidableController.jump(index: nextIndex, animated: false)
                }
            } else {
                content[currentIndex].lifeCycleObject.didCancelSliding()
                unloadView(around: currentIndex)
            }
        } else {
            if !isForcedToSlide {
                updateTitleScrollOffset(contentOffset: actualContentOffset, pageSize: pageSize)
            }
            shiftKeyboardIfNeeded(offset: -(actualContentOffset - lastContentOffset))
        }
        lastContentOffset = actualContentOffset
    }
    
    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        didFinishForceSlide?()
        didFinishSlideAction?()
        didFinishSlideAction = nil
        titleSlidableController.isSelectionAllowed = true
        titleSlidableController.titleView.isScrollEnabled = true
        if isForcedToSlide {
            unloadView(around: currentIndex)
        }
        isForcedToSlide = false
        sourceIndex = nil
        destinationIndex = nil
    }
    
    // MARK: - ViewableImplementation
    public var view: UIView {
        return containerView
    }
}

private typealias PrivateSlideController = SlideController
private extension PrivateSlideController {
    func calculateContentPageSize(direction: SlideDirection, titleViewAlignment: TitleViewAlignment, titleViewPosition: TitleViewPosition, titleSize: CGFloat) -> CGFloat {
        var contentPageSize: CGFloat!
        if direction == SlideDirection.horizontal {
            if (titleViewAlignment == TitleViewAlignment.left || titleViewAlignment == TitleViewAlignment.right) && titleViewPosition == TitleViewPosition.beside {
                contentPageSize = containerView.frame.width - titleSlidableController.titleView.titleSize
            } else {
                contentPageSize = containerView.frame.width
            }
        } else {
            if titleViewPosition == TitleViewPosition.beside &&  titleViewAlignment == TitleViewAlignment.top {
                contentPageSize = containerView.frame.height - titleSlidableController.titleView.titleSize
            } else {
                contentPageSize = containerView.frame.height
            }
        }
        return contentPageSize
    }
    
    private func scrollToPage(pageIndex: Int, animated: Bool) {
        titleSlidableController.jump(index: pageIndex, animated: animated)
        didFinishSlideAction = contentSlidableController.scroll(fromPage: currentIndex, toPage: pageIndex, animated: animated)
        if slideDirection == SlideDirection.horizontal {
            lastContentOffset = contentSlidableController.slideContentView.contentOffset.x
        } else {
            lastContentOffset = contentSlidableController.slideContentView.contentOffset.y
        }
    }
    
    func updateTitleScrollOffset(contentOffset: CGFloat, pageSize: CGFloat) {
        let actualIndex = Int(contentOffset / pageSize)
        let offset = contentOffset - lastContentOffset
        var startIndex: Int
        var destinationIndex: Int
        if  offset < 0 {
            startIndex = actualIndex + 1
            destinationIndex = startIndex - 1
        } else {
            startIndex = actualIndex
            destinationIndex = startIndex + 1
        }
        titleSlidableController.shift(delta: offset, startIndex: startIndex, destinationIndex: destinationIndex)
    }
    
    func determineScrollingDirection(lastContentOffset: CGFloat, currentContentOffset: CGPoint) -> ScrollingDirection {
        switch slideDirection! {
        case .vertical:
            if lastContentOffset > currentContentOffset.y {
                return .up
            } else {
                return .down
            }
        case .horizontal:
            if lastContentOffset > currentContentOffset.x {
                return .right
            } else {
                return .left
            }
        }
    }
    
    func loadView(pageIndex: Int) {
        loadViewIfNeeded(pageIndex: pageIndex - 1)
        loadViewIfNeeded(pageIndex: pageIndex, truePage: true)
        loadViewIfNeeded(pageIndex: pageIndex + 1)
    }
    
    func unloadView(around currentIndex: Int) {
        let loadedViewIndices = [currentIndex - 1, currentIndex, currentIndex + 1]
        let unloadIndices = content.indices.filter{ !loadedViewIndices.contains($0) }
        unloadIndices.forEach { unloadView(at: $0) }
    }
    
    func unloadView(at index: Int) {
        guard content.indices.contains(index) else {
            return
        }
        if contentSlidableController.containers[index].hasContent {
            contentSlidableController.containers[index].unloadView()
            content[index].lifeCycleObject.viewDidUnload()
        }
    }
    
    func loadViewIfNeeded(pageIndex: Int, truePage: Bool = false) {
        if content.indices.contains(pageIndex) {
            if !contentSlidableController.containers[pageIndex].hasContent {
                contentSlidableController.containers[pageIndex].load(view: content[pageIndex].lifeCycleObject.view)
                content[pageIndex].lifeCycleObject.viewDidLoad()
            }
            if truePage {
                if isOnScreen {
                    if currentIndex != pageIndex {
                        if content.indices.contains(currentIndex) {
                            content[currentIndex].lifeCycleObject.didDissapear()
                        }
                        currentIndex = pageIndex
                    }
                    content[pageIndex].lifeCycleObject.didAppear()
                } else {
                    currentIndex = pageIndex
                }
            }
        }
    }
    
    func shiftKeyboardIfNeeded(offset: CGFloat) {
        guard content.indices.contains(currentIndex) else {
            return
        }
        if content[currentIndex].lifeCycleObject.isKeyboardResponsive && slideDirection == SlideDirection.horizontal {
            if let keyBoardView = findKeyboardWindow() {
                var frame = keyBoardView.frame
                frame.origin.x = frame.origin.x + offset
                keyBoardView.frame = frame
            }
        }
    }
    
    func findKeyboardWindow () -> UIWindow? {
        for window in UIApplication.shared.windows {
            if window.isKind(of: NSClassFromString("UIRemoteKeyboardWindow")!) {
                return window
            }
        }
        return nil
    }
}