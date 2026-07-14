# LookInside

LookInside is a Mac app that lets you click through your iOS or macOS app UI and see every view, layer, frame, and property live.

![Preview](./Resources/SCR-20260502-svqx.jpeg)

## Use it

1. Download LookInside from the [Releases page](http://172.17.13.138/ftpfanxingroot/LookInside/LookInside.dmg).
2. Add the server package to the app you want to inspect.
3. Run your app.
4. Open LookInside on your Mac and pick the running app.

## Use it with AI agents

LookInside 2.3.11 and later include a local MCP server for Codex, Claude, Cursor, Windsurf, VS Code, and other MCP clients. Agents can inspect hierarchies, attributes, screenshots, and UI changes through the app you already opened in LookInside.

See the [MCP configuration and usage guide](docs/mcp.md).

## What you can inspect

- UIKit, AppKit, and SwiftUI view trees
- Frames, layers, screenshots, and resolved properties
- SwiftUI modifiers and layout details
- Live property changes while your app is running

## License

GPL-3.0. See [`LICENSE`](LICENSE).
