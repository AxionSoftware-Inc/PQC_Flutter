# antiQ brand assets

The master transparent mark is `antiq-mark.png`. Platform assets are generated
by:

```bash
python tool/brand/build_brand_assets.py
```

The generator requires Pillow and creates mobile, web, desktop, adaptive icon,
and light/dark splash variants. Do not hand-edit generated platform PNG files.

Brand rules:

- Product spelling is always `antiQ`.
- Use the Q mark without extra shapes or a padlock.
- Primary background: `#07090D`.
- Primary foreground: `#F6F9FC`.
- Accent: `#45D7E8`.
- Keep the mark's clear space at least 13% of its rendered size.
