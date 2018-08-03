# PAPERBOY Todo

## Next release

- [ ] show version number at the bottom of the UI.
- [ ] use xdg path for writing config file instead of home direcory.
- [ ] warn when importing an already existing filename.
- [ ] use http://hackage.haskell.org/package/path for filepaths.
- [ ] option to open the document while in the middle of a rename/import.

## Done

- [x] use nix for CI and releases.
- [x] compiled releases for Mac & Linux so that people other than Haskellers with 24Gb worth of stack/GHC installs can actually use this.
- [x] homebrew for mac
- [x] exception handling if `pdftotext` or `pdfinfo` are missing.
- [x] pin nixpkgs version.

## Possible future features

- allow renaming files after they have been imported.
- refresh if any files move outside of the application.
- nicer "first-use experience": Right now we simply write a default config file. It would be good to have an initial setup dialog asking for the inbox and library folder paths.
- try out circleCI
- move away from ghr for releases and use inbuilt travis uploads instead.
- release .deb and .rpm packages.
- subfolders.
- ability to mark documents as 'to-read'.
- make the utility work without a UI -> import documents using only command-line flags.
- search functionality -> build a search index based on the content we get from `pdftotext`.
- send files to a personalized email address, pboy will check and pull that.
- tag files to sync to phone (or kindle).