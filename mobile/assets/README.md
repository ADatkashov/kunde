# Bundled artwork

- `illustrations/*.png`: Microsoft Fluent Emoji, 3D assets, MIT license.
  Source: https://github.com/microsoft/fluentui-emoji/tree/main/assets
  Exact source paths follow `<English emoji name>/3D/<emoji_name>_3d.png`.
  Copyright and license are preserved in `illustrations/LICENSE.txt`.
- `photos/food.jpg`: hamburger photograph, Unsplash photo `1568901346375-23c9450c58cd`.
  Source: https://unsplash.com/photos/sc5sTPMrVfk
  Download: https://images.unsplash.com/photo-1568901346375-23c9450c58cd
  License: https://unsplash.com/license (free commercial use; downloaded 2026-11-15).
  Used only as a promotional illustration, never as a merchant/product photograph.
- `photos/food-banner.webp`: generated promotional artwork for KUNDE.
  Used as decorative banner imagery.
- `photos/nearby-*.webp`: generated category illustrations for the home
  recommendations. They do not depict a catalog merchant or item.
- `photos/education-hero.webp`: original generated illustrative artwork for the Education landing screen. The student and location are illustrative.
- Almaty mountains and K mark: original vector artwork in the Flutter source.

All artwork is bundled for offline rendering; no third-party image requests are
needed for the home screen. Catalog-supplied HTTPS product photos retain their
existing behavior and local fallback.

- `fonts/NotoSans-*.ttf`: Noto Sans, SIL Open Font License 1.1.
  Source: https://github.com/notofonts/noto-fonts/tree/main/hinted/ttf/NotoSans
  License retained in `fonts/LICENSE.txt`. Bundled Regular/Medium/Bold/ExtraBold/Black
  ensure Cyrillic, Kazakh and tenge glyphs render consistently offline.

- DEV Flowers catalog: illustrative flower photo `photo-1490750967868-88aa4486c946`,
  https://images.unsplash.com/photo-1490750967868-88aa4486c946,
  https://unsplash.com/license; synthetic items and prices do not represent an actual offer.

- `photos/home-services.jpg` and `photos/beauty.jpg`: Unsplash category artwork
  (https://images.unsplash.com/photo-1581578731548-c64695cc6952 and
  https://images.unsplash.com/photo-1503951914875-452162b0f3f1).
  https://unsplash.com/license. Illustrative photos for the Home and Beauty
  categories, without suggesting they show any particular provider.

- `photos/groceries.jpg`: Unsplash category artwork
  (https://images.unsplash.com/photo-1542838132-92c53300491e),
  https://unsplash.com/license. Illustrative photo for the Grocery catalog.
