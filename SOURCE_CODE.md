# Source Code Availability

When distributing binaries of 绣绘呆棉整合版, provide the corresponding source code for the exact binary release.

The source release must include:

- The upstream Inkscape source at commit `7923d92`, or a fork/tag containing that source.
- The upstream Ink/Stitch source at commit `0312dac`, or a fork/tag containing that source.
- The patches under `patches/`.
- The overlay files under `overlays/`.
- Build scripts and packaging instructions.
- License and notice files.
- Third-party license information for bundled runtime dependencies.

Recommended release layout:

- `绣绘呆棉整合版-<version>-windows-x64.zip` or installer package.
- `绣绘呆棉整合版-<version>-source.zip`.
- A release note linking to the public source tag.

Do not distribute a binary-only package without a matching source archive or public source tag.

