# AppIcon production source

AppIcon-source.png preserves the upstream MIT-licensed raster master unchanged (SHA256 888b46407d47a18546fca17517b5308c760a865a4e6ac1d7de576c6df0cb7212).

The existing cyan C and orange highlight are retained without redrawing or recoloring. scripts/produce_icons.py cleans exterior alpha with the measured backing-plate bounds (138,145)-(1117,1073), preserves the original aspect ratio, centers a maximum 824 px plate in a transparent 1024 px macOS canvas, and emits the macOS 1x/2x variants plus the asset catalog. Pillow is required only to regenerate the artwork. The standard app build consumes the checked-in artwork using Xcode actool.

Regenerate into a temporary directory, review AppIcon.png and preview-light-dark.png, compare hashes, then copy the reviewed AppIcon.png, AppIcon.icns, AppIcon.iconset and Assets.xcassets to Resources. Do not regenerate checked-in source during a verification command.

The icon remains compatible with macOS 13 via the multi-resolution ICNS, while CFBundleIconName binds the compiled asset catalog. No public distribution or new brand concept is implied.

For current macOS, Resources/AppIcon.icon is compiled by actool as the native icon composition. The existing raster is scaled by 1.32 inside the system-owned enclosure to avoid applying the legacy padding twice; the backdrop uses the existing deep-blue identity. No C or highlight pixels are redrawn. The descriptor was authored locally and validated by actool; Icon Composer GUI was not used because its first-run license was not accepted. The native descriptor format is empirical, so compiler verification and actual Dock checks remain required when changing Xcode versions.

The complete 16–1024 px legacy ICNS is copied after native compilation and remains the fallback for older macOS. Assets.xcassets retains the reviewed raster variants, while the app build uses the .icon composition to avoid the automatic light surround.
