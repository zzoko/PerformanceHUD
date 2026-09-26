# Changelog

[← Back to README](../README.md)

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
