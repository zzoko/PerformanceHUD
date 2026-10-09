# Changelog

[← Back to README](../README.md)

### v2.3

- Added memory-pressure history graphs for Vertical mode, with a fixed 0–100 scale, a 30-second history, a current-reading dot, and a fading fill. **Text / Graph** offers neutral and colored meters (**A1 / A2**) and history graphs (**B1 / B2**). History graphs use a taller pressure row and switch to the matching meter in Horizontal mode.
- Refined fan layout: **Both** places RPM between the fan badge and a wider bar, with balanced spacing in both layouts. Fan bars align with the memory-pressure history width.
- New settings default to colored pressure history (**B2**, or **A2** in Horizontal), fan **Total** (bar only), and **Chip & OS** off. Existing saved choices are preserved.
- Matched the Low Power Mode battery yellow to pressure yellow and removed the divider below FAN when it is the last visible category.
- Updated the Controls guide and documentation screenshots.

### v2.2

- Added a **Liquid Glass** strength slider from Clear to Frosted, with live adjustment, remembered settings, and **Follow macOS** enabled by default. Unified the Appearance and Liquid Glass selectors.
- Added an independent **Pressure** control with **Text / Meter / Color meter** choices and text emphasis, separate from memory Details. Color meter is selected by default; meter segments sit side by side in Vertical and stack in Horizontal, replacing its warning triangle.
- Improved memory-pressure responsiveness with one-second sampling and aligned horizontal Battery readings with the CPU/GPU column layout.

### v2.1

- Redesigned the menu’s category controls with aligned reading rows, consistent emphasis buttons, and individually selectable Misc options. Existing settings and category switches are preserved.
- FAN is now disabled on fanless Macs, with a clear **Not available** status.
- Smoothed transitions between all Auto hide modes, including returning directly to the collapsed FPS arrow. The matching **Animation** checkbox keeps instant changes available.
- Kept the collapsed FPS height and divider position steady when changing its display mode.
- Updated the **Controls guide** for the redesigned controls, removed the outdated illustration, and refreshed the documentation screenshots.

### v2.0

- Added **Check for updates** to download and install official updates from inside the app, with signed update verification and retained HUD preferences. Available to purchased copies and source builds.
- Added optional **Weekly / Monthly** update checks, off by default. Available updates appear in the menu without interrupting games; downloads and restarts remain your choice.
- Added optional **Auto start on login**, off by default.
- Simplified **Reset** and **Auto hide** into single-row controls and refined the menu layout.

### v1.9

- Added **Edit hotkeys** for showing/hiding the HUD, starting/stopping logging, and cycling Light / Dark / Follow system. Defaults are **Option–H**, **Option–L**, and **Option–A**, with saved custom combinations, clearing, and a separate reset to defaults. Moving the HUD defaults to **Option + drag**, with a choice of Option, Control, Shift, or Command and a matching menu hint.
- Added an optional **Misc** category for the focused process, Metal output resolution, display refresh rate, experimental Game Mode status, and macOS thermal state, with independent reading buttons and CSV logging support. Disabled by default and available in Vertical alignment only.
- Added a battery Charge reading, showing charging or discharging in watts, with Always / Auto / Off modes, independent emphasis, and CSV logging. Auto is the default: idle readings keep their space in Vertical, while Horizontal reclaims it until charging or discharging resumes. Samples live battery voltage and current once per second, with a battery-controller fallback. Reorganized the Battery controls; remaining readings move right when an option is turned off.
- Kept the Vertical HUD width consistent when toggling readings and categories; FPS Value alone retains its compact layout.
- Refined Battery and fan controls, shortened **Usage** to **Use**, and renamed **SoC Power** to **SoC combined**. Usage emphasis is off by default; existing saved choices are preserved.

### v1.8

- Added **Start / Stop logging** for selected HUD readings, sampled once per second into a CSV for spreadsheets and graphs. Logs save to the Desktop when stopped, when the HUD is disabled, or when the app quits; unavailable values stay blank. Includes an independent first-use explanation and recovery files if saving fails.
- Added an independent **Animated** checkbox for Auto hide, enabled by default. FPS and All options can now hide/show instantly while retaining their automatic behavior; Off keeps everything visible.
- Fixed switching from collapsed FPS to All options briefly expanding the FPS category before hiding the HUD. Hiding now continues from the visible compact layout.
- Replaced the custom captured glass with Apple’s regular **Liquid Glass** and a softer exterior shadow. Appearance now offers **Light**, **Dark**, and **Follow system**.
- Improved glass reliability during resizing, layout changes, and show/hide transitions by removing capture restarts, held frames, and the checkerboard fallback. Native glass and shadows follow the HUD directly.
- Significantly reduced PerformanceHUD’s own glass-processing overhead by eliminating continuous screen capture and custom per-frame rendering. macOS now renders the glass directly.
- **Screen Capture permission is no longer required** for the HUD’s glass effect.
- Added a display-refresh compatibility workaround for the observed game FPS cap with native glass.
- Updated the **Controls guide** for logging and macOS Liquid Glass settings, and refreshed all six HUD and menu screenshots.

### v1.7

- Refreshed HUD typography with consistent label, reading, and emphasized reading styles.
- Refined the HUD’s rounded corners for a softer, macOS-inspired appearance.
- Added an **FPS value emphasis** toggle beneath Value, enabled by default, and made the fan RPM emphasis control clearer.
- SoC power emphasis now defaults to off.
- Improved memory spacing in both layouts and fixed FPS text shifting vertically when switching layouts.
- Made **Don’t show this again** choices for Auto hide and Reset all options independent and preserved across resets.
- Updated the **Controls guide**, refreshed all six HUD and menu screenshots, and updated the app version to **1.7**.

### v1.6

- Added **Auto hide → FPS / Off / All options** near the top of the menu, replacing the FPS category’s Static / Dynamic selector. FPS is the default and collapses only the FPS area; Off keeps everything visible; All options hides the whole HUD after three seconds without FPS readings and reveals it when readings return. Existing Static / Dynamic choices are preserved. Enable / Disable remains the master switch.
- Matched FPS and whole-HUD transitions to a quicker **0.4-second animation** in both layouts, with rounded moving edges and a fixed capture footprint. Hidden vertical rows stay independent of the shrinking horizontal viewport, avoiding layout conflicts during collapse. Reduce Motion skips animations. All options keeps FPS detection active even with the FPS category unchecked, and pauses other readings and glass capture once hidden. Its explanation includes **Don’t show this again**.
- Expanded **Size** from **0.5× to 2×**, with finer **0.01× steps** and the same 1× default, allowing more adjustment for different display scaling and fullscreen games.
- Added separate **Reset → Position / Size** buttons, with **All options** below. Size returns to 1×; All options resets size, position, and the other HUD options after confirmation while preserving macOS permissions. Added **Don’t show this again** for reset confirmations, remembered across resets. Updated the Controls guide to match.
- Fixed menu labels shifting sideways when switching to **Horizontal** alignment, and matched the reset shortcut hint’s text intensity to the native Enable / Disable shortcut.
- Stabilized the left edge of the **60-second FPS history** as older samples leave the graph, preventing the brief gap or jump after the graph fills.
- Softened glass transitions when changing size, layout, or appearance by briefly retaining the previous glass image and matching text colors while a fresh capture arrives. The HUD also waits briefly for its first usable glass frame when appearing, reducing checkerboard flashes. Capture delays or failures still fall back to the dark checkerboard, now with slightly larger squares.
- Refined the HUD with **softer continuous corners** that scale consistently from 0.5× to 2×, including shadows, fallback glass, and collapse animations.
- Fixed the reproduced **power-reading dropouts under sustained load**: the helper now keeps its power reader running continuously instead of restarting it every five samples, and allows more time for the first reading. Stalled readers still recover automatically, empty exits back off before retrying, and the reader is cleaned up when the helper stops. Validated under RDR2 load and Low Power Mode.
- Fixed **HUD clipping in exclusive-fullscreen games** such as Metro Exodus when changing layout, size, or visible readings. The HUD now reapplies its current dimensions after macOS finishes changing the display mode, preventing an older window size from clipping the contents. Verified in both layouts.
- Updated the **Controls guide** for Auto hide, resets, sizing, and glass transitions. Added a compact version badge beside Download options in the README, linking to the changelog. Updated the app version to **1.6**.

### v1.5

- Combined **FPS** and **FPS History** into one menu category with **Value / History / Both** and **Static / Dynamic** selectors, aligned with the other controls. FPS is enabled with Both and Dynamic selected by default for fresh settings and Options reset. Saved choices are preserved; hiding FPS remembers the selected mode. Horizontal uses Value only and restores the history choice when returning to Vertical.
- Added **Dynamic FPS** in both layouts. After three seconds without available readings, Vertical rolls up the selected FPS value/history section and Horizontal collapses the FPS value sideways. Readings returning smoothly expand the section again; Static keeps the existing fixed layout.
- Kept a faint directional arrow and the divider beside following readings while FPS is collapsed: **downward in Vertical**, **rightward in Horizontal**. The arrow also remains when FPS is the only enabled category.
- Kept the full expanded background-capture area fixed during FPS transitions, avoiding capture restarts as the visible HUD changes size. Returning readings can reverse an animation already in progress, and macOS **Reduce Motion** skips the animation.
- Replaced **FAN 1 / FAN 2 / FAN AVG** labels with compact rounded-square badges in both layouts. Centred numbers identify individual fans; **A** identifies Average. The badges use a faint outline and scale with the HUD.
- Unified fan bar widths across layouts and display modes. Total-only keeps the same bar size when aligned to the right in Vertical. Bars sit evenly between the badge and RPM text, and horizontal RPM values use the same trailing spacing as other readings. Live RPM updates retain stable HUD dimensions.
- Updated the **Controls guide** for the combined FPS controls, dynamic behaviour, and fan badges. Updated the app version to **1.5**.

### v1.4

- Added **Follow system** beneath the Appearance choices, enabled by default for fresh settings and Options reset. It automatically uses the existing Light or Dark HUD background to match macOS, including changes while the app is running. Existing manual choices are preserved; Clear remains a manual choice.
- Added a **FAN** category after MEM in both layouts, with **Total / RPM / Both** choices and Both selected by default. Total shows a speed bar relative to each fan’s reported maximum, without percentage text; RPM shows numeric speed.
- Added **Average** with **Vertical / Horizontal / Both** choices, enabled for Horizontal by default. With two or more fans, **FAN AVG** shows the mean RPM and the average of each fan’s speed relative to its own maximum. With one fan, Average is unchecked and unavailable, and the HUD shows **FAN 1**.
- Added optional **RPM highlighting** through the thin line beneath RPM and Both. It starts off, applies to individual and averaged readings, and remembers the choice while RPM is hidden.
- Adapted fan rows to both layouts. Vertical uses a longer, right-aligned bar for Total alone and a shorter bar alongside RPM; Horizontal uses compact bars and faint dividers between fans. FAN labels match other category labels. Fan rows fit the existing vertical width, and live values and status changes keep stable dimensions to avoid unnecessary background-capture restarts.
- Added read-only fan detection through AppleSMC, without requiring the power helper or changing cooling settings. On fanless Macs, **FAN defaults to off** for fresh settings and Options reset; it can still be enabled manually to show **No fans detected**, with Usage and Average unchecked and disabled. Manual category choices are preserved, and read failures do not turn FAN off. Missing readings remain distinct from a valid 0 RPM; averages require valid readings from all fans. Live RPM validation on a Mac with fans is still pending.
- Added a scrollable, resizable **Controls guide**, ordered to match the menu, covering reading controls, highlighting, layouts, memory-pressure symbols, fan controls and availability, Follow system, shortcuts, and the Power Helper. Includes a checkbox illustration showing normal and highlighted states.
- Moved the app version into the guide header and removed the version row from the menu. Updated the app version to **1.4**.
- Removed repeated explanatory tooltips now covered by the guide, while keeping current error and troubleshooting messages.
- Shortened **Unified Memory** to **MEM** in the menu and guide headings; the guide still explains the full name.
- Widened the menu’s shared label column so checkbox groups and the power connector stay clear of category names, even when labels are shortened.
- Made Unified Memory **Details** and **Usage** independent in both layouts. **Total / App / Both** selects the source for either, so details remain available with usage hidden. Horizontal pressure indicators keep their position beside SWP without resizing the HUD when pressure changes.
- Fixed the **Details** checkbox appearance when Unified Memory is disabled: its saved checkmark and emphasis remain visible but dimmed, matching the other controls.

### v1.3

- Moved **Size** above **Alignment** in the menu.
- Refined the **FPS** label’s left alignment in Vertical and Horizontal so its position matches when switching layouts.
- Renamed menu categories and controls: **Apple Neural Engine → ANE**, **Package Power → SoC Power**, **RAM → Unified Memory**, **Device Info → Chip & OS**, **Background → Appearance**, and **Close App → Quit**.
- Updated HUD labels: **RAM → MEM** (including **MEM (app)**), **PKG → SOC**, and **Power source → Power Source**. SoC Power still shows the combined CPU, GPU, and ANE power estimate, not whole-Mac consumption.
- Matched the **Energy** checkbox’s box and checkmark to the other reading controls, without adding a boldness strip.
- Updated tooltips and helper setup text to match the new names. ANE’s tooltip spells out **Apple Neural Engine**, and Chip & OS describes the **chip name and macOS version**.

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
