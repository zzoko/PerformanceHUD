# Changelog

[← Back to README](../README.md)

### v1.2

#### Layout and appearance

- Added **Horizontal alignment** alongside the existing Vertical layout, which remains the default. Categories sit in a single row with stronger dividers between them and faint dividers between Total and App readings when Both is selected.
- Adapted the horizontal layout with compact **BAT / ADP** battery labels, no “Power source” heading, and an FPS section matching the compact vertical FPS-only width. FPS History and Device Info are unavailable in Horizontal; their selections are remembered when returning to Vertical.
- Refined label-to-value spacing, battery temperature spacing, and reading alignment in both layouts. Fixed text clipping at smaller horizontal sizes and the slight FPS-label shift when switching alignment.
- Replaced the Light glass background with a brighter, softer version designed to keep text readable over changing scenery.
- Expanded HUD placement to the full display, including the areas near the Dock and menu bar. The visible panel stays within the display edges.

#### Readings and controls

- Added **Apple Neural Engine power**, shown as **ANE** in the HUD and enabled by default. It uses the existing power helper. ANE utilization percentage, temperature, and per-app readings are not offered because reliable readings have not been established.
- Made **Package Power** independently selectable in both layouts, regardless of which CPU, GPU, or ANE power options are enabled. Shown as **PKG** after ANE and before RAM, it remains the combined CPU, GPU, and ANE power estimate—not whole-Mac consumption. ANE and PKG watts follow the CPU watts column in Vertical.
- Replaced automatic emphasis of the rightmost reading with **independent highlighting**. CPU/GPU power, temperature and usage, ANE power, RAM usage and details, battery temperature, and Package Power can each use faint or bolder text at the same size.
- Added **split checkbox controls**: the checkbox shows or hides a reading, while its attached strip independently toggles boldness. The strip indicates the saved emphasis and dims while unavailable or hidden. Turning a reading off remembers its emphasis; options without highlighting keep a regular checkbox.
- Replaced the separate Total Use and Only focused app checkboxes with a **Usage checkbox and Total / App / Both selector** for CPU, GPU, and RAM. Total remains the default; usage and Package Power are highlighted by default, with other highlightable readings faint by default.
- Added a **RAM Details** control, enabled and unhighlighted by default. Details follow the selected usage mode, become unavailable while Usage is off, and remember their visibility and emphasis. Highlighting affects the values rather than the Physical, Swap, and Pressure labels.
- Added compact horizontal RAM details: **PHY** and **SWP**, with Total RAM usage at the end. An outlined triangle indicates warning memory pressure and a filled triangle indicates critical pressure; normal pressure has no triangle. App RAM shows the tracked process’s physical memory; swap and pressure remain system-wide and appear with Total.
- Reorganized the menu with separate groups for power/temperature and usage, aligned Details and Energy controls, and a visual connector for the power categories and Package Power. Background choices now use a segmented selector, with Transparent renamed **Clear**.
- Added **Reset → Position / Options**. Position resets placement immediately. Options asks for confirmation, then restores the default categories, readings, highlighting, usage modes, alignment, size, and background and enables the HUD, while preserving position and permissions.
- Updated tooltips to explain the new controls, layout differences, helper requirements, memory-pressure symbols, and the distinction between system CPU usage and per-app CPU usage that can exceed 100%.

#### Reliability

- Stabilized horizontal sizing across blank/live readings, memory-pressure changes, and larger watt, app CPU, swap, and FPS values to reduce unnecessary glass-capture restarts.
- Added bounded continuity for power readings: a brief sampling gap can retain the last valid reading for up to five seconds from its original timestamp. Stopping, sleeping, or disconnecting clears retained values. Added a scoped activity declaration while power monitoring runs to help background updates continue while a game is in front, without preventing normal system sleep.

**Known issue:** intermittent disappearance of watt readings has still been observed in games. The changes above are mitigations, not a confirmed fix.

### v1.1

- Reworked the HUD UI with refined spacing, slightly stronger main labels, and neatly aligned readings grouped on the right. The rightmost enabled reading uses the larger number style, including when only power or temperature is shown.
- Improved the FPS history graph with a smoother, slightly bolder line, more visible FPS variations, and a translucent gradient fill that fades down to the divider.
- Added a more compact HUD width when FPS is the only enabled category.
- Added estimated battery temperature for supported MacBooks, alongside a small “Power source” heading and the Battery / Power Adapter label. Battery Temperature and Energy can be toggled separately and are enabled by default.
- Added estimated CPU and GPU power consumption in watts, shown to one decimal place. A Package row shows the combined CPU, GPU, and Neural Engine power estimate when both CPU and GPU power readings are enabled and visible. Power is enabled by default for both; the Package estimate does not represent whole-Mac power consumption.
- Added first-launch setup and menu controls for the optional power-reading helper, shared by CPU, GPU, and Package watts.
- Improved the menu with Power options for CPU and GPU, grouped battery controls, and more consistent alignment. Position now appears above Size.
- Replaced the size buttons with a rounded fill slider covering 0.75× to 1.25× in 0.05× steps, with live resizing and 1× as the default.

### v1.0

- Initial release.
