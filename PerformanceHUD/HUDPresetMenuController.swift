import AppKit

/// The same native submenu used by the menu's other app settings.
@MainActor
final class HUDPresetMenuController: NSObject {
    let menuItem = NSMenuItem(title: "Preset", action: nil, keyEquivalent: "")
    private let submenu = NSMenu(title: "Preset")
    private let onSelect: (HUDPresetSelection) -> Void
    private let onSave: () -> Void
    private let onManage: () -> Void
    private var choices: [HUDPresetSelection] = []
    private struct SavedIdentity: Equatable {
        let id: UUID
        let name: String
    }
    private var displayedSelection: HUDPresetSelection?
    private var displayedSavedPresets: [SavedIdentity] = []

    init(onSelect: @escaping (HUDPresetSelection) -> Void,
         onSave: @escaping () -> Void, onManage: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onSave = onSave
        self.onManage = onManage
        super.init()
        submenu.autoenablesItems = false
        menuItem.submenu = submenu
    }

    func update(selection: HUDPresetSelection, savedPresets: [HUDSavedPreset]) {
        let identities = savedPresets.map { SavedIdentity(id: $0.id, name: $0.name) }
        guard selection != displayedSelection || identities != displayedSavedPresets else { return }
        displayedSelection = selection
        displayedSavedPresets = identities
        let font = NSFont.menuFont(ofSize: 0)
        var name = selection.title
        while (name as NSString).size(withAttributes: [.font: font]).width > HUDCategoryLayout.width * 0.55,
              name.count > 1 {
            name = String(name.dropLast(name.hasSuffix("…") ? 2 : 1)) + "…"
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = HUDCategoryLayout.categoryLeading
            + HUDCategoryLayout.categoryLabelInset - HUDMenuLayout.labelLeading
        paragraph.tabStops = [NSTextTab(textAlignment: .left,
            location: HUDCategoryLayout.readingLeading + HUDCategoryLayout.readingLabelInset
                - HUDMenuLayout.labelLeading)]
        menuItem.title = "Preset: \(selection.title)"
        menuItem.attributedTitle = NSAttributedString(string: "Preset\t\(name)",
            attributes: [.font: font, .paragraphStyle: paragraph])
        submenu.removeAllItems()
        choices = []
        for builtIn in HUDBuiltInPreset.allCases {
            addChoice(.builtIn(builtIn), title: builtIn.title, selected: selection)
        }
        if !savedPresets.isEmpty {
            submenu.addItem(.separator())
            for saved in savedPresets {
                addChoice(.saved(saved.id, saved.name), title: saved.name, selected: selection)
            }
        }
        submenu.addItem(.separator())
        let save = NSMenuItem(title: "Save current as…", action: #selector(saveCurrent), keyEquivalent: "")
        save.target = self
        submenu.addItem(save)
        let manage = NSMenuItem(title: "Manage presets…", action: #selector(managePresets), keyEquivalent: "")
        manage.target = self
        submenu.addItem(manage)
    }

    private func addChoice(_ choice: HUDPresetSelection, title: String, selected: HUDPresetSelection) {
        let item = NSMenuItem(title: title, action: #selector(selectPreset(_:)), keyEquivalent: "")
        item.target = self
        item.tag = choices.count
        item.state = choice == selected ? .on : .off
        choices.append(choice)
        submenu.addItem(item)
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard choices.indices.contains(sender.tag) else { return }
        onSelect(choices[sender.tag])
    }

    @objc private func saveCurrent() { onSave() }
    @objc private func managePresets() { onManage() }

}
