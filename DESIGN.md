# KUNDE design context

## Product and audience
Consumer Super App for everyday life in Almaty, then Kazakhstan. Russian,
Kazakh and English. The approved Premium UI 2.1 concept is the Home and assistant visual reference.
Food, Grocery and booking retain their existing DEV contracts.

## Visual direction
Compact Almaty header and search, three violet/lilac/gold promotion cards,
a two-row category grid, a horizontal meal banner and a nearby photo rail.
The dark canvas is navy and the light canvas is cool white. AI has a luminous
violet mark and a localized Soon status. Rewards, membership and notifications
explain their availability when opened.

## Typography and layout
Bundled Noto Sans (KundeSans) covers Cyrillic and Kazakh. Home uses 4/8 dp
spacing, 16 dp outer insets and 16 dp radius on tiles and promotions.
The category grid reflows from four to three or two columns for narrow
viewports and large text. The compact category tiles use Material icons.

## Runtime ownership
packages/kunde_design owns shared palette tokens. Consumer and Partner adapt
them through their existing role-specific Material themes.
KundeArt owns bundled illustration rendering and original mountain artwork;
HomeHeader/CategoryGrid/FoodBanner/QuickAction own home composition.
Food widgets own imagery fallback, catalog cards and checkout progress.
KundeLocalizations, HomeStrings and ShellStrings own foundation localization.
Existing Food/Booking Russian copy remains unchanged in language scope.
Material components own focus, keyboard, dialogs, scrollbars and state semantics.
See UX-CONTRACT.md and mobile/test/features for behavior and visual coverage.

## Assets and availability
Bundled Fluent Emoji (MIT), Unsplash promotional hamburger photo, original
vector artwork. Sources and licenses: mobile/assets/README.md. Merchant cards use catalog data and actual images when supplied. A Material
icon is the nearby fallback. Service photos illustrate categories.
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
