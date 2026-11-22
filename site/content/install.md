---
title: Install
description: Set up the downloaded app, or build PerformanceHUD yourself from source.
---

Requires an Apple silicon Mac running macOS 27.0 or later. See [Display compatibility](/compatibility/) for how the HUD behaves in fullscreen games. If you bought the app, follow **Downloaded app**; if you're compiling it yourself, skip to **Build from source**.

## Downloaded app

### Allow the app to open

The app isn't notarized by Apple, so macOS blocks its first launch. Only approve a copy from the official PerformanceHUD download.

1. Unzip the download and move **PerformanceHUD.app** into **Applications**.
2. Open it. When macOS warns that it can't verify the developer, dismiss the alert. Don't move the app to the Trash.
3. Go to **System Settings → Privacy & Security** and choose **Open Anyway** next to the PerformanceHUD message, then confirm.
4. Look for the **lightning-bolt icon in the menu bar**. That's where all the controls are.

If there's no **Open Anyway** option, or macOS says the app is damaged, stop and [report it](/support/) with the exact message. [Apple's guidance on opening downloaded apps](https://support.apple.com/en-us/102445)

### Allow Background App Activity

CPU, GPU, ANE and SOC watt readings come from a small power helper that macOS needs to approve.

1. On first launch, choose **Enable Power Readings**.
2. If macOS asks, open **System Settings → General → Login Items & Extensions → Login Items**, turn on **PerformanceHUD** under **Background App Activity**, and authenticate.

Prefer to skip it? Choose **Not Now**. Everything else works without the helper, and you can set it up later from **Power Helper** in the menu.

**If watts stay blank:** open **Power Helper** in the menu and use **Open Approval Settings…**, **Update Power Helper…** or **Repair Power Helper…**, depending on the status shown there. Muted Power checkboxes mean the helper isn't set up or approved; clicking **Power** opens the same options.

### Updating or removing the app

PerformanceHUD checks for updates once on first launch, and you can use **Check for updates** in the menu at any time or turn on **Weekly** or **Monthly** checks. Nothing downloads or restarts without your say, and your settings are kept. If prompted after an update, choose **Update Helper**.

If an update says the app is in a read-only or temporary location, move **PerformanceHUD.app** into Applications and open it from there.

To uninstall, set **Auto start on login → Off**, choose **Power Helper → Remove Power Helper**, then quit the app and move it to the Trash.

### Starting automatically

Set **Auto start on login → On** to open PerformanceHUD with your saved settings when you log in.

## Build from source

1. Download a version from the [list of releases](https://github.com/zzoko/PerformanceHUD/tags), or clone the repository with `git clone https://github.com/zzoko/PerformanceHUD.git`, and read the [license](/license/). Personal builds and modifications are permitted; compiled redistribution is not.
2. Open **PerformanceHUD.xcodeproj** in a version of Xcode that includes the macOS 27 SDK or newer.
3. For each target, **PerformanceHUD** and **PowerHelper**, open **Signing & Capabilities** and replace the author's development team with your own, using matching Apple signing certificates for both. You don't need the author's signing credentials. Ad-hoc (unsigned, local-only) builds can show the other readings but can't enable the power helper.
4. Choose the **PerformanceHUD** scheme and **My Mac**, then **Product → Run**.
5. For CPU, GPU, ANE and SOC watts, follow **Allow Background App Activity** above.

A locally built app usually doesn't need the Gatekeeper approval from the downloaded-app steps. Xcode fetches the pinned Sparkle dependency automatically when building. You only need Xcode to build from source, not to install the downloaded app.

Source builds get the same first-launch update check and **Check for updates** option. Installing an update replaces your build with the official one: your HUD preferences are kept, but local code changes are not. The [license](/license/) attached to how you obtained your copy still applies.

To run the regression checks before releasing changes, see [Running the tests](https://github.com/zzoko/PerformanceHUD/blob/main/Tests/README.md).
