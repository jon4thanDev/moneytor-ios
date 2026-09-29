# moneytor
A simple budgeting app that helps you set spending limits by category without tracking every cent.

## Running
Open `Moneytor.xcodeproj` in Xcode and run on a simulator or device (iOS 17+).

The project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). After adding or removing files, run `xcodegen generate`.

The first build needs Xcode's Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`), and Xcode will ask you to trust the `mlx-swift` package plugin.

## Assistant
Tap the sparkles button on either tab to open the assistant. Type (Chat) or talk (Speak) in English, e.g. "Spent 200 on lunch yesterday", "Add salary 25k", or "How much is left in food?". It asks follow-up questions for anything missing and confirms before saving.

- **Basic mode** (default) uses a built-in parser: no download, works offline.
- **Smart AI** is an optional ~1 GB download (Qwen3 1.7B via [MLX](https://github.com/ml-explore/mlx-swift-lm)) that runs on-device and understands looser phrasing. Test it on a real iPhone; MLX doesn't run on the Simulator's GPU.
