# Third-Party Licenses

The Windows preview build bundles runtime components and Python packages in addition to Inkscape and Ink/Stitch.

Before a public binary release, generate a complete third-party license inventory from the installed package directory:

- `build/install_dir/lib/python*/LICENSE.txt`
- `build/install_dir/lib/python*/site-packages/*dist-info/LICENSE*`
- `build/install_dir/share/inkscape/doc/`
- `build/install_dir/share/inkscape/extensions/`
- MSYS2/UCRT64 runtime libraries included in the final installer or zip package.
- Fonts, icons, palettes, templates and example files.

Do not publish the binary until this file is replaced or accompanied by a generated release-specific license inventory.

