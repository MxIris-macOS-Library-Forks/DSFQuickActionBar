import AppKit
import DSFAppearanceManager

extension DSFQuickActionBar {
    @objc(DSFQuickActionBarWindow) final class Window: EphemeralWindow {
        // The actionbar instance
        var quickActionBar: DSFQuickActionBar!

        // To minimise the number of calls during edit
        let debouncer = DSFDebounce(seconds: 0.2)

        // Allow the window to become key
        override var canBecomeKey: Bool { return true }
        override var canBecomeMain: Bool { return currentCanBecomeMainWindow }

        override func resignFirstResponder() -> Bool {
            return true
        }

        var currentCanBecomeMainWindow: Bool = true

        // Should the control display keyboard shortcuts?
        var showKeyboardShortcuts: Bool = false

        // The placeholder text for the edit field
        var placeholderText: String = "" {
            didSet {
                editLabel.placeholderString = placeholderText
            }
        }

        private var _currentSearchText: String = ""
        private(set) var currentSearchText: String {
            get { _currentSearchText }
            set {
                _currentSearchText = newValue
                editLabel.stringValue = newValue
            }
        }

        // Primary container
        private lazy var primaryStack: NSStackView = {
            let stack = NSStackView()
            stack.identifier = NSUserInterfaceItemIdentifier("primary")
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.orientation = .vertical
            stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

            stack.setContentHuggingPriority(.required, for: .horizontal)
            stack.setContentHuggingPriority(.required, for: .vertical)
            stack.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

            stack.setHuggingPriority(.required, for: .vertical)

            stack.needsLayout = true

            return stack
        }()

        // The edit label
        internal lazy var editLabel: NSTextField = {
            let t = DSFTextField()
            t.translatesAutoresizingMaskIntoConstraints = false
            t.wantsLayer = true
            t.drawsBackground = false
            t.isBordered = false
            t.isBezeled = false
            t.font = NSFont.systemFont(ofSize: 24, weight: .regular)
            t.textColor = NSColor.textColor
            t.alignment = .left
            t.isEnabled = true
            t.isEditable = true
            t.isSelectable = true
            t.cell?.wraps = false
            t.cell?.isScrollable = true
            t.maximumNumberOfLines = 1
            t.placeholderString = DSFQuickActionBar.DefaultPlaceholderString

            t.focusRingType = .none

            t.setContentHuggingPriority(.defaultLow, for: .horizontal)
            t.setContentHuggingPriority(.defaultHigh, for: .vertical)
            t.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            t.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)

            return t
        }()

        // The upper left image
        private lazy var searchImage: NSImageView = {
            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
            imageView.addConstraint(NSLayoutConstraint(item: imageView, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .width, multiplier: 1, constant: 24))
            imageView.addConstraint(NSLayoutConstraint(item: imageView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .height, multiplier: 1, constant: 40))
            imageView.imageScaling = .scaleProportionallyUpOrDown

            let image = self.quickActionBar.searchImage!
            imageView.image = image
            return imageView
        }()

        // The async task indicator
        private let asyncActivityIndicator = DSFDelayedIndeterminiteRadialProgressIndicator()

        // The stack of '[image] | [edit field]'
        private lazy var searchStack: NSStackView = {
            let stack = NSStackView()
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.detachesHiddenViews = true
            stack.orientation = .horizontal

            if let _ = self.quickActionBar.searchImage {
                stack.addArrangedSubview(searchImage)
            }

//            stack.addArrangedSubview(editLabel)
//            editLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
//            editLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
            let textContainer = NSView()
            textContainer.translatesAutoresizingMaskIntoConstraints = false
            textContainer.addSubview(editLabel)

            NSLayoutConstraint.activate([
                editLabel.leadingAnchor.constraint(equalTo: textContainer.leadingAnchor),
                editLabel.trailingAnchor.constraint(equalTo: textContainer.trailingAnchor),
                editLabel.centerYAnchor.constraint(equalTo: textContainer.centerYAnchor),
                textContainer.heightAnchor.constraint(greaterThanOrEqualTo: editLabel.heightAnchor),
            ])

            stack.addArrangedSubview(textContainer)

            textContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)

            stack.addArrangedSubview(asyncActivityIndicator)

            stack.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            stack.setContentHuggingPriority(.defaultHigh, for: .vertical)

            stack.setHuggingPriority(.required, for: .vertical)

            return stack
        }()

        // The results view
        lazy var results: DSFQuickActionBar.ResultsView = {
            let r = DSFQuickActionBar.ResultsView()
            r.translatesAutoresizingMaskIntoConstraints = false
            r.setContentHuggingPriority(.defaultLow, for: .horizontal)
            r.quickActionBar = self.quickActionBar
            r.showKeyboardShortcuts = self.showKeyboardShortcuts
            r.configure()

            return r
        }()

        // Is set to true when the user 'activates' an item in the result list
        internal var userDidActivateItem: Bool = false

        // The task if the control is waiting for search results
        private var currentSearchRequestTask: DSFQuickActionBar.SearchTask?
    }
}

extension DSFQuickActionBar.Window {
    @inlinable func reloadData() {
        results.reloadData()
    }
}

extension DSFQuickActionBar.Window {
    // Build the quick action bar display
    internal func setup(parentWindow: NSWindow? = nil, initialSearchText: String?) {
        autorecalculatesKeyViewLoop = true

        // Make sure we adopt the effective appearance
        UsingEffectiveAppearance(ofWindow: parentWindow) {
            /// The background view for the window
            let content = DSFPrimaryRoundedView()
            self.contentView = content

            /// Primary view content
            primaryStack.wantsLayer = true
            primaryStack.translatesAutoresizingMaskIntoConstraints = false
            primaryStack.setContentHuggingPriority(.required, for: .horizontal)
            primaryStack.setContentHuggingPriority(.required, for: .vertical)

            // Attach the stack into the window view
            content.contentView.addSubview(primaryStack)

            NSLayoutConstraint.activate([
                content.contentView.topAnchor.constraint(equalTo: primaryStack.topAnchor),
                content.contentView.leadingAnchor.constraint(equalTo: primaryStack.leadingAnchor),
                content.contentView.trailingAnchor.constraint(equalTo: primaryStack.trailingAnchor),
                content.contentView.bottomAnchor.constraint(equalTo: primaryStack.bottomAnchor),
            ])

            self.backgroundColor = NSColor.clear
            self.isOpaque = false

            // We set 'titled' here AND 'borderless' as it seems to give us a bolder
            // drop shadow than just 'borderless' itself. How odd!
            self.styleMask = [.titled, .fullSizeContentView, .borderless]

            // Make sure the user cannot move the window
            self.isMovable = false
            self.isMovableByWindowBackground = false

            // Add the search stack (the search text field and any imagery)
            primaryStack.addArrangedSubview(searchStack)

            results.isHidden = true
            primaryStack.addArrangedSubview(results)

            primaryStack.needsLayout = true

            editLabel.delegate = self

            self.makeFirstResponder(editLabel)
            self.invalidateShadow()
            self.level = .init(23)

            if let parent = parentWindow {
                self.order(.above, relativeTo: parent.windowNumber)
            }

            self.primaryStack.layoutSubtreeIfNeeded()

            if let initialSearchText = initialSearchText {
                self.currentSearchText = initialSearchText
            }

            ensuringMainThreadAsync { [weak self] in
                self?.searchTermDidChange()
            }
        }
    }
}

extension DSFQuickActionBar.Window {
    // Called when the user presses 'escape' when the window is present
    override func cancelOperation(_: Any?) {
        // Tell the window to lose its initial responder status, which will close it.
        resignMain()
    }

    // Called from the results view when the user presses the left arrow
    func pressedLeftArrowInResultsView() {
        makeFirstResponder(editLabel)
    }
}

extension DSFQuickActionBar.Window {
    func provideResultIdentifiers(_ identifiers: [AnyHashable]) {
        results.identifiers = identifiers
    }
}

// MARK: - Search

extension DSFQuickActionBar.Window {
    private func searchTermDidChange() {
        // Must be called on the main thread
        precondition(Thread.isMainThread)

        // Cancel any outstanding search task.
        // Note we don't need to lock here, as we are guaranteed to be on the main thread
        cancelCurrentSearchTask()

        // If we have no content source, there's nothing left to do
        guard let contentSource = quickActionBar.contentSource else { return }

        let currentSearch = editLabel.stringValue
        _currentSearchText = currentSearch

        asyncActivityIndicator.startAnimation(self)

        // Create a search task
        let itemsTask = DSFQuickActionBar.SearchTask(searchTerm: currentSearch) { [weak self] results in
            DispatchQueue.main.async { [weak self] in
                guard let `self` = self else { return }
                self.cancelCurrentSearchTask()
                self.updateResults(currentSearch: currentSearch, results: results ?? [])
            }
        }

        // Store the current search so that we can cancel it if needed
        currentSearchRequestTask = itemsTask

        // And finally ask the content source to retrieve an array of identifiers that match
        contentSource.quickActionBar(quickActionBar, itemsForSearchTermTask: itemsTask)
    }

    private func updateResults(currentSearch: String, results: [AnyHashable]) {
        // Must always be called on the main thread
        precondition(Thread.isMainThread)

        asyncActivityIndicator.stopAnimation(self)
        self.results.currentSearchTerm = currentSearch
        self.results.identifiers = results
    }

    private func cancelCurrentSearchTask() {
        // Must be called on the main thread
        precondition(Thread.isMainThread)

        // Mark the request as invalid
        currentSearchRequestTask?.completion = nil
        currentSearchRequestTask = nil
    }
}

// MARK: - Text control handling

extension DSFQuickActionBar.Window: NSTextFieldDelegate {
    func controlTextDidChange(_: Notification) {
        debouncer.debounce { [weak self] in
            self?.searchTermDidChange()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(moveDown(_:)) {
            return results.selectNextSelectableRow()
        } else if commandSelector == #selector(moveUp(_:)) {
            return results.selectPreviousSelectableRow()
        } else if commandSelector == #selector(insertNewline(_:)) {
            let currentRowSelection = results.selectedRow
            guard currentRowSelection >= 0 else { return false }
            results.rowAction()
            return true
        } else if
            showKeyboardShortcuts,
            let event = currentEvent,
            event.modifierFlags.contains(.command),
            let chars = event.characters,
            let index = Int(chars) {
            return results.performShortcutAction(for: index)
        }

        return false
    }
}
