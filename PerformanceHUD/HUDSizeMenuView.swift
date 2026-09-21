import AppKit

@MainActor
final class HUDSizeMenuView: NSView {

    // MARK: - Output

    var onScaleSelected:
        ((HUDScale) -> Void)?

    // MARK: - State

    private var selectedScale:
        HUDScale

    // MARK: - Buttons

    private var scaleButtons:
        [HUDScale: NSButton] = [:]

    // MARK: - Init

    init(
        selectedScale: HUDScale
    ) {

        self.selectedScale =
            selectedScale

        super.init(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 220,
                height: 28
            )
        )

        setupView()
    }

    required init?(
        coder: NSCoder
    ) {
        fatalError()
    }

    // MARK: - Setup

    private func setupView() {

        let sizeLabel =
            NSTextField(
                labelWithString:
                    "Size"
            )

        sizeLabel.font =
            NSFont.menuFont(
                ofSize: 0
            )

        sizeLabel.textColor =
            .labelColor

        let stack =
            NSStackView()

        stack.orientation =
            .horizontal

        stack.alignment =
            .centerY

        stack.spacing =
            10

        stack.translatesAutoresizingMaskIntoConstraints =
            false

        stack.addArrangedSubview(
            sizeLabel
        )

        for scale in HUDScale.allCases {

            let button =
                createButton(
                    for: scale
                )

            scaleButtons[scale] =
                button

            stack.addArrangedSubview(
                button
            )
        }

        addSubview(
            stack
        )

        NSLayoutConstraint.activate([

            stack.leadingAnchor.constraint(
                equalTo:
                    leadingAnchor,
                constant: 30
            ),

            stack.centerYAnchor.constraint(
                equalTo:
                    centerYAnchor
            ),

            stack.trailingAnchor.constraint(
                lessThanOrEqualTo:
                    trailingAnchor,
                constant: -12
            )
        ])

        updateSelection()
    }

    // MARK: - Button

    private func createButton(
        for scale: HUDScale
    ) -> NSButton {

        let button =
            NSButton(
                title:
                    buttonTitle(
                        for: scale
                    ),
                target: self,
                action:
                    #selector(
                        scaleClicked(_:)
                    )
            )

        button.isBordered =
            false

        button.bezelStyle =
            .inline

        button.font =
            NSFont.menuFont(
                ofSize: 0
            )

        button.tag =
            Int(
                scale.rawValue
                * 100
            )

        return button
    }

    private func buttonTitle(
        for scale: HUDScale
    ) -> String {

        switch scale {

        case .normal:
            return "1x"

        case .large:
            return "1.25x"

        case .extraLarge:
            return "1.5x"
        }
    }

    // MARK: - Click

    @objc
    private func scaleClicked(
        _ sender: NSButton
    ) {

        let rawValue =
            Double(sender.tag)
            / 100.0

        guard
            let scale =
                HUDScale(
                    rawValue:
                        rawValue
                )
        else {
            return
        }

        selectedScale =
            scale

        updateSelection()

        onScaleSelected?(
            scale
        )
    }

    // MARK: - Selection Appearance

    private func updateSelection() {

        for (
            scale,
            button
        ) in scaleButtons {

            if scale ==
                selectedScale {

                button.font =
                    NSFont.systemFont(
                        ofSize:
                            NSFont.menuFont(
                                ofSize: 0
                            )
                            .pointSize,
                        weight:
                            .semibold
                    )

            } else {

                button.font =
                    NSFont.menuFont(
                        ofSize: 0
                    )
            }
        }
    }
}
