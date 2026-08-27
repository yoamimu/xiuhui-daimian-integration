# Third-Party License Inventory: macOS v0.1.0

This inventory was generated from the final Apple Silicon application bundle. The Intel package contains the same application and runtime component families for its target architecture. It is an index to the bundled license texts, not a replacement for those texts.

## Primary Projects

| Component | License |
| --- | --- |
| Inkscape | GPL-2.0-or-later |
| Ink/Stitch | GPL-3.0-or-later |
| Xiuhui Daimian integration changes | GPL-3.0-or-later |

The application contains the Inkscape `COPYING`, `LICENSE`, and `AUTHORS` files under `Contents/Resources/share/inkscape/doc/`. Ink/Stitch's license is under its nested `Contents/Resources/` directory.

## Bundled Python Packages

| Package | Version | License |
| --- | --- | --- |
| click | 8.4.2 | BSD-3-Clause |
| cryptography | 49.0.0 | Apache-2.0 OR BSD-3-Clause |
| Flask | 3.1.3 | BSD-3-Clause |
| importlib_metadata | 8.7.1 | Apache-2.0 |
| itsdangerous | 2.2.0 | BSD-3-Clause |
| MarkupSafe | 3.0.3 | BSD-3-Clause |
| numpy | 2.2.6 | BSD-3-Clause |
| trimesh | 5.0.0 | MIT |
| Werkzeug | 3.1.8 | BSD-3-Clause |

Package-specific license files are included in the corresponding `*.dist-info` directories or package source directories inside the Ink/Stitch bundle.

## Native Runtime Families

The self-contained application also includes the following runtime families. Exact versions and license alternatives are governed by each component's bundled or upstream license text.

| Runtime family | License family |
| --- | --- |
| GTK, GLib, Pango, gdk-pixbuf, gtkmm, glibmm, cairomm, libsigc++, GtkSourceView, libspelling, libthai | LGPL family and component-specific terms |
| Cairo | LGPL-2.1-or-later OR MPL-1.1 |
| Poppler, GSL, Potrace, LZO | GPL family and component-specific terms |
| NSS, NSPR, libcdr, librevenge, libvisio, libwpd, libwpg | MPL family and component-specific terms |
| HarfBuzz, fontconfig, libxml2, Little CMS, Graphene, GraphicsMagick, pixman | Permissive MIT-style or component-specific licenses |
| ICU | Unicode License |
| libpng, libtiff, JPEG, OpenJPEG, WebP, zstd, double-conversion, PCRE2 | Permissive project-specific or BSD-style licenses |
| FreeType | FreeType License OR GPL |
| libassuan, libgpg-error, GPGME | LGPL/GPL family as applicable |
| X11 and XCB libraries | MIT/X11 family |

Other included support libraries include datrie, enchant, epoxy, fribidi, Boehm GC, graphite2, gettext/libintl, liblzma, libltdl, and libzstd. Their respective license terms remain applicable.

## Fonts and Assets

The Ink/Stitch bundle contains 138 embedded font directories. Each directory includes its own `LICENSE` file next to the font assets. Inkscape icons, palettes, templates, examples, and extension assets remain subject to their individual upstream notices.

## Corresponding Source

- Release source: the GitHub-generated source archive for tag `macos-v0.1.0`.
- Pinned upstream source bundle: [`xiuhui-upstream-sources.tar.gz`](https://github.com/yoamimu/xiuhui-daimian-integration/releases/download/upstream-sources-r1/xiuhui-upstream-sources.tar.gz)
- Pinned upstream source SHA-256: `b4525c08299e4f8b9fedbe38424f60cdd2bf19c96c8fdd30f61fddf012d6d40f`
- Integration build identifier embedded in both apps: `xiuhui-b1ad7aa-local`.

For redistribution, preserve the license texts inside the application bundle and provide the corresponding source and integration repository required by the applicable licenses.
