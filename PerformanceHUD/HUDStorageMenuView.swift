import AppKit

@MainActor
final class HUDStorageMenuView: HUDCategoryMenuView {
    private var options: HUDStorageOptions
    var onChange: ((HUDStorageOptions) -> Void)?
    private let master = HUDResourceMasterButton(title: "Storage", target: nil, action: nil)
    private let location = NSSegmentedControl(labels: HUDStorageLocation.allCases.map { $0.rawValue.capitalized },
        trackingMode: .selectOne, target: nil, action: nil)
    private let freeSpaceHighlight = HUDEmphasisButton()
    private let details = HUDReadingCheckbox(title: "Details")

    init(options: HUDStorageOptions) {
        self.options = options
        super.init()
        master.target = self
        master.action = #selector(toggleCategory)
        master.setAccessibilityLabel("Show Storage")
        location.target = self
        location.action = #selector(selectLocation)
        location.setAccessibilityLabel("Storage drives")
        freeSpaceHighlight.target = self
        freeSpaceHighlight.action = #selector(toggleFreeSpaceHighlight)
        freeSpaceHighlight.setAccessibilityLabel("Emphasize Storage free space")
        details.target = self
        details.action = #selector(toggleDetails)
        details.setControlAccessibilityLabel("Storage Details")
        details.onHighlight = { [weak self] in
            guard let self else { return }
            self.options.detailsHighlighted.toggle()
            changed()
        }
        setCategory(master)
        setRows([.init(reading: NSView(), mode: location, emphasis: freeSpaceHighlight),
                 .init(reading: NSView(), mode: details, emphasis: details.emphasisControl)])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("Use init(options:)") }

    @objc private func toggleCategory() { options.enabled = master.state == .on; changed() }
    @objc private func toggleDetails() { options.details = details.state == .on; changed() }
    @objc private func toggleFreeSpaceHighlight() {
        options.freeSpaceHighlighted = freeSpaceHighlight.state == .on
        changed()
    }
    @objc private func selectLocation() {
        guard HUDStorageLocation.allCases.indices.contains(location.selectedSegment) else { return }
        options.location = HUDStorageLocation.allCases[location.selectedSegment]
        changed()
    }

    private func changed() { refresh(); onChange?(options) }

    private func refresh() {
        master.state = options.enabled ? .on : .off
        location.selectedSegment = HUDStorageLocation.allCases.firstIndex(of: options.location)!
        location.isEnabled = options.enabled
        freeSpaceHighlight.isEnabled = options.enabled
        freeSpaceHighlight.state = options.freeSpaceHighlighted ? .on : .off
        details.isEnabled = options.enabled
        details.state = options.details ? .on : .off
        details.emphasized = options.detailsHighlighted
    }
}
