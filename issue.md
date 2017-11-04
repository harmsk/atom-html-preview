## Description

There is a recent problem where Atom crashes after typing just a few characters
of HTML code while having the `html-preview` pane open.

## Environment

* Atom version: 1.21.2 x64 for macOS
* All non-core packages disabled, except for `html-preview`.

## Steps to reproduce

1. Start a new HTML file
2. Open `html-preview` pane
3. Enter the code: `<div>`, watching the preview page as the code is entered.
4. The preview pane will flicker as each character is entered.
5. On entering the last character, Atom crashes.
