# PerformanceHUD

## ↓ Download options &nbsp;<a href="docs/CHANGELOG.md"><img src="docs/images/app-version.svg" alt="App version 1.8 — view changelog" width="56" height="30" align="top"></a>

Get the ready-built app for a one-time **$3.99**, or build it yourself for free. Both offer the same features, with no subscription or feature unlocks.

<p>
  <a href="https://ko-fi.com/s/01a23ddc51"><img src="docs/images/download-kofi.svg" alt="Download app on Ko-fi — $3.99 one-time" width="250" height="64"></a>&nbsp;
  <a href="docs/INSTALL.md#build-from-source"><img src="docs/images/build-from-source.svg" alt="Build it yourself — free, requires Xcode" width="250" height="64"></a>
</p>

Purchases support me and the continuing of maintenance and development of PerformanceHUD. The paid app can be used personally or commercially, including in monetized videos and streams. Free source builds and modifications are for **personal, non-commercial use**. Resale and external redistribution are not permitted. See the [license](LICENSE) for details.

If you prefer to build the app yourself but would still like to support it, **GitHub Sponsorships** will offer another way to contribute. A link will be added once approved.

![Repository activity: daily Git clones over the last 14 days](https://raw.githubusercontent.com/zzoko/PerformanceHUD/stats/repository-activity.svg)

## ✦ About PerformanceHUD

<table>
<tr>
<td>

<details>
<summary><strong>Take a closer look — features, screenshots &amp; controls</strong></summary>

PerformanceHUD is a tiny (<4 MB) app that displays a performance overlay over games and apps. You can use it as just an FPS display, or also show CPU, GPU, and memory usage, temperatures, power readings, fan speeds, and battery information for a deeper overview of how your Mac is handling the workload.

The HUD is customized from the menu bar. You can choose which readings to display and highlight, swap between vertical and horizontal layouts, adjust the size and appearance, and move the overlay where you want it. You can also turn it on and off at any time, even if the game is already running, or log selected readings to a CSV for spreadsheets and graphs. There’s a built-in Controls Guide explaining in detail what each option in the menu does and how it works.

I’ve put a lot of thought into keeping the overlay easy to read and the controls organized, even as more features have been added. Attention to detail and making something genuinely useful that I would want to use myself and would improve my macOS experience have been the goal. There are many small details, from the battery icon dynamically changing with your Mac’s power state to Apple’s Liquid Glass effect that lets the HUD blend naturally into whatever’s on screen.

<table>
  <tr>
    <th colspan="2">Dark appearance</th>
  </tr>
  <tr>
    <td width="33%" valign="top" align="center">
      <a href="docs/images/HUD_vertical_dark.png"><img src="docs/images/HUD_vertical_dark.png" alt="PerformanceHUD vertical HUD with a dark background" width="240"></a><br>
      <sub>Vertical HUD</sub>
    </td>
    <td width="67%" valign="top" align="center">
      <a href="docs/images/HUD_menu_dark.png"><img src="docs/images/HUD_menu_dark.png" alt="PerformanceHUD menu controls in dark mode" width="480"></a><br>
      <sub>Menu controls</sub>
    </td>
  </tr>
  <tr>
    <td colspan="2" align="center">
      <a href="docs/images/HUD_horizontal_dark.png"><img src="docs/images/HUD_horizontal_dark.png" alt="PerformanceHUD horizontal HUD with a dark background" width="760"></a><br>
      <sub>Horizontal HUD</sub>
    </td>
  </tr>
</table>

<table>
  <tr>
    <th colspan="2">Light appearance</th>
  </tr>
  <tr>
    <td width="33%" valign="top" align="center">
      <a href="docs/images/HUD_vertical_light.png"><img src="docs/images/HUD_vertical_light.png" alt="PerformanceHUD vertical HUD with a light background" width="240"></a><br>
      <sub>Vertical HUD</sub>
    </td>
    <td width="67%" valign="top" align="center">
      <a href="docs/images/HUD_menu_light.png"><img src="docs/images/HUD_menu_light.png" alt="PerformanceHUD menu controls in light mode" width="480"></a><br>
      <sub>Menu controls</sub>
    </td>
  </tr>
  <tr>
    <td colspan="2" align="center">
      <a href="docs/images/HUD_horizontal_light.png"><img src="docs/images/HUD_horizontal_light.png" alt="PerformanceHUD horizontal HUD with a light background" width="760"></a><br>
      <sub>Horizontal HUD</sub>
    </td>
  </tr>
</table>

<details>
<summary>Watch PerformanceHUD in-game</summary>

[![Watch PerformanceHUD in-game on YouTube](https://img.youtube.com/vi/-b_t999Q9pQ/hqdefault.jpg)](https://youtu.be/-b_t999Q9pQ)

</details>

</details>

</td>
</tr>
</table>

<br>

## Display compatibility

<details>
<summary>View display modes and fullscreen compatibility</summary>

- **Windowed and borderless:** Recommended display mode for games and apps for universal compatibility and "just works". The HUD stays visible over apps and games, with correct scaling and Retina rendering independent of the game’s rendering resolution.
- **Fullscreen — native macOS games:** Generally works in fullscreen mode. Some games change macOS UI scaling in fullscreen exclusive, making the HUD and other system UI appear smaller or larger. The HUD follows macOS scaling; so if for example a game is set to 4K macOS scale may become a lot smaller including the HUD, in such cases adjusting the **Size** in the PerformanceHUD menu between **0.5× to 2×** can make it fit better. Confirmed working in fullscreen exclusive in Stray and Minecraft using Vulkan rendering.
- **Fullscreen — Windows games through compatibility layers:** Games running through CrossOver or similar tools only show the HUD reliably when the fullscreen resolution matches your desktop’s current “looks like” resolution or its 2× Retina equivalent. Confirmed working with matching resolutions in Red Dead Redemption 2 and Resident Evil Requiem through CrossOver. If the HUD disappears, try one of these resolutions or switch to windowed/borderless.

To find your desktop resolution, open **System Settings → Displays** and hover over the selected scaling thumbnail, or choose **Show List**. For the 2× Retina equivalent, double both dimensions. For example, a 13-inch MacBook Air uses **1470×956** or **2940×1912** with its default scaling setting. So for the HUD to be visible in RDR2 running through CrossOver while the game is set to fullscreen the in-game resolution would need to be set to either **1470x956** or **2940x1912**. Windowed and borderless mode avoids needing matching resolutions as mentioned.

</details>

## Requirements

<details>
<summary>View system requirements</summary>

- Apple silicon Mac (M-series), running macOS 27.0 or later.

</details>

## More resources

- [Differences between PerformanceHUD and MetalHUD](docs/METAL_HUD_COMPARISON.md)
- [Bugs & suggestions](docs/FEEDBACK.md)
- [Changelog](docs/CHANGELOG.md)
- [Privacy & access](docs/PRIVACY_AND_ACCESS.md)
- [License](LICENSE)
