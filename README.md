# PerformanceHUD

## ↓ Download options

➤ Source is available to build and modify for personal use under the [personal-use license](LICENSE). You can build it yourself for free using the [installation instructions](docs/INSTALL.md).

➤ <img src="https://cdn3.emoji.gg/emojis/24562-kofi.png" width="20" height="20" alt="Ko-fi"> **[Download on Ko-fi](https://ko-fi.com/s/01a23ddc51)** — Get the ready-built app for a one-time $3.99 to support me and the development time that has gone into it. It offers the same features as the version you build yourself. No subscription or feature unlocks.

**➤ GitHub sponsorships** — If you prefer to build the app yourself but would still like to support it, direct GitHub sponsorships will offer another way to contribute. A link will be added once approved.

## Display compatibility

<details>
<summary>View display modes and fullscreen compatibility</summary>

- **Windowed and borderless:** Recommended display mode for games and apps for universal compatibility and "just works". The HUD stays visible over apps and games, with sharp Retina rendering independent of the game’s rendering resolution.
- **Fullscreen — native macOS games:** Generally works across any fullscreen resolutions, though the HUD resolution may be automatically changed to the same resolution as the game. Confirmed working in fullscreen in the native macOS Steam version of Stray and Minecraft using Vulkan render.
- **Fullscreen — Windows games through compatibility layers:** Games running through CrossOver or similar tools typically require the fullscreen resolution to match your desktop’s current “looks like” resolution or its 2× Retina rendering resolution. Confirmed working in fullscreen (with matching resolutions) in Red Dead Redemption 2 and Resident Evil Requiem through CrossOver. If the HUD disappears, try setting the game to one of these resolutions or switch to windowed/borderless.

To find your current resolution, open **System Settings → Displays** and hover over the selected scaling thumbnail, or choose **Show List**. For the 2× Retina equivalent, double both dimensions. For example, a 13-inch MacBook Air uses 1470×956 or 2940×1912 with its default scaling setting. So for the HUD to be visible in fullscreen game running through translation layers like Red Dead Redemption 2 the in-game resolution would need to be set to either 1470x956 or 2940x1912. Windowed and borderless mode avoids needing matching resolutions as mentioned.

</details>

## What is this?

PerformanceHUD is a small, customizable performance overlay for macOS that keeps useful stats visible while you play. Use it as a minimal FPS display, or add resource usage, temperatures, and power readings for a fuller picture of how your Mac is handling a game.

Show only what matters to you: FPS and its 60-second history, system or focused-app CPU/GPU/RAM usage, chip temperatures and power consumption, memory details, and battery information. Available readings depend on your hardware and the app being tracked.

Everything is controlled from the menu bar. Toggle individual metrics, adjust the size and background, and position the HUD wherever it fits your screen. You can turn it on while a game is already running.

## Showcase

<table>
  <tr>
    <td width="30%" valign="top">
      <img src="docs/images/HUD_desktop_transparent.png" alt="PerformanceHUD on the desktop with resource usage, temperatures, memory details, and battery status" width="100%">
    </td>
    <td width="70%" valign="top">
      <img src="docs/images/HUD_menu_settings.png" alt="PerformanceHUD menu with size, position, background, and individual metric controls" width="100%">
    </td>
  </tr>
</table>

<details>
<summary>Watch PerformanceHUD in-game</summary>

[![Watch PerformanceHUD in-game on YouTube](https://img.youtube.com/vi/-b_t999Q9pQ/hqdefault.jpg)](https://youtu.be/-b_t999Q9pQ)

</details>

## Compared with Apple's Metal performance HUD

- [Compare features and tradeoffs](docs/METAL_HUD_COMPARISON.md)

## Future ideas — under consideration

- [Explore potential future additions](docs/FUTURE_IDEAS.md)

## Changelog

- [See what changed in each version](docs/CHANGELOG.md)

## Privacy & access

- [Read about data sources, permissions, and the power helper](docs/PRIVACY_AND_ACCESS.md)

## Requirements

- [Check system and permission requirements](docs/REQUIREMENTS.md)

## License

- [Read the personal-use license](LICENSE)
