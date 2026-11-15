# KUNDE design context

## Product and audience
Consumer Super App for everyday life in Almaty, then Kazakhstan. Russian,
Kazakh and English. The owner’s premium redesign brief (2026-11-15) is the
visual reference: bright white, emerald, illustrated services, generous rounded
surfaces. Existing Food/Grocery and booking DEV behavior remains authoritative;
see docs/product/food-mvp.md and docs/product/booking-mvp.md.

## Visual direction
White canvas #FFFFFF, emerald #00875A, forest #004A37, mint #E1F7EB,
ink #142B23, pale surface #F5F7F6. Light mode is explicit, including when the
phone uses dark mode. KundeTheme owns Material semantic roles. The snowy Almaty
silhouette, volume illustrations and dark forest Food photography form the
signature; surrounding UI stays restrained. AI stays visibly «Скоро».

## Typography and layout
Bundled Noto Sans (KundeSans) with Cyrillic/Kazakh coverage; 30/24/20 display,
17/16 body, 10.5–12 compact category/caption text. Wordmark uses heavy weight.
Content max width 600–640 dp, 16–24 dp insets, 16–24 dp radii. Controls have
at least 48 dp touch targets. Five category columns at 360 dp and above;
large text and smaller screens reflow to four/three columns. Content scrolls
naturally within safe areas. Main target widths: Samsung 360/390/412 dp.

## Runtime ownership
mobile/lib/shared/theme/kunde_theme.dart owns tokens; screens consume ThemeData.
KundeArt owns bundled illustration rendering and original mountain artwork;
HomeHeader/CategoryGrid/FoodBanner/QuickAction own home composition.
Food widgets own imagery fallback, catalog cards and checkout progress.
KundeLocalizations, HomeStrings and ShellStrings own foundation localization.
Existing Food/Booking Russian copy remains unchanged in language scope.
Material components own focus, keyboard, dialogs, scrollbars and state semantics.
See UX-CONTRACT.md and mobile/test/features for behavior and visual coverage.

## Assets and availability
Bundled Fluent Emoji (MIT), Unsplash promotional hamburger photo, original
vector artwork. Sources and licenses: mobile/assets/README.md. Merchant cards
use catalog data and bundled illustrations; no fabricated ratings or photos.
Remote HTTPS product imagery retains fallback behavior. Synthetic merchants
keep the ДЕМО label. City picker lists only the supported city, Almaty.

## Navigation and compatibility
Five tabs: Home, Search, Orders, Services, Profile. This owner request supersedes
the older four-tab design decision; Profile remains directly reachable to
preserve addresses, language, consents, support, partner tools and logout.
Services uses the same server booking gate as Home. Language/logout are in the
Profile app bar; the main feed has one branded header. Backend, capability
flags, pricing, stock, idempotent ordering and authentication are unchanged.

## Avoid
No empty actions, fake notifications, ratings or availability claims. No
credential forms, token diagnostics, remote fonts, security changes or
unapproved payment/AI integrations. Golden baselines cover home widths,
Food/Grocery, cart, checkout, history and profile; device/TalkBack checks remain
separate evidence from widget/golden tests.
