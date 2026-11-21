---
title: Display compatibility
description: Requirements, display modes and fullscreen behavior for PerformanceHUD.
---

## Requirements

- Apple silicon Mac (M-series), running macOS 27.0 or later.

## Display modes

- **Windowed and borderless (recommended):** The most compatible option; it just works. The HUD stays visible over any game or app, correctly scaled and Retina-sharp regardless of the game's rendering resolution.
- **Fullscreen — native macOS games:** Generally works. Some games change macOS display scaling in exclusive fullscreen, and since the HUD follows macOS scaling, it can end up smaller or larger along with the rest of the system UI. Setting a game to 4K, for example, can shrink it noticeably. If that happens, adjust **Size** in the PerformanceHUD menu (**0.5×** to **2×**) until it fits. Confirmed working in exclusive fullscreen in Stray, and in Minecraft with Vulkan rendering.
- **Fullscreen — Windows games through compatibility layers:** With CrossOver or similar tools, the HUD only appears reliably when the game's fullscreen resolution matches your desktop's current "looks like" resolution, or its 2× Retina equivalent. Confirmed working at matching resolutions in Red Dead Redemption 2 and Resident Evil Requiem through CrossOver. If the HUD disappears, switch to one of those resolutions or to windowed/borderless.

## Finding your desktop resolution

Open **System Settings → Displays** and hover over the selected scaling thumbnail, or choose **Show List**. Double both numbers for the 2× Retina equivalent. A 13-inch MacBook Air at its default scaling, for example, uses **1470×956**, so RDR2 in fullscreen through CrossOver would need an in-game resolution of **1470×956** or **2940×1912**. Windowed and borderless modes don't need a matching resolution at all.
