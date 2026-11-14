# Chinese Variants Linter for macOS

[简体中文](README.md) | **English**

The macOS version of Chinese Variants Linter. It lives in the menu bar and checks whether the Chinese text in any app's input fields matches a target region (Simplified Chinese, Chinese (Taiwan), Chinese (Hong Kong) or Traditional Chinese), in both character forms and regional wording, and offers in-place replacement.

Text is processed on your Mac only. Nothing is uploaded and the app never connects to the network. Detection results match the browser extension, [chinese-variants-linter](../chinese-variants-linter).

## Features

- Script checks (Simplified/Traditional mismatches) and regional wording checks (for example 软件 / 軟體).
- Allowed words and custom phrases, with CSV and OpenCC dictionary import and export.
- Live marks, a suggestion popup and one-key replacement. In apps whose text cannot be read, use global shortcuts to check or convert the selected text.
- Password fields are skipped by default, and checking can be turned on or off per app.

## License

[MIT](LICENSE)
