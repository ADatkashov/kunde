# KUNDE design context

## Product and audience
Consumer Super App for everyday life in Almaty, then Kazakhstan. Russian,
Kazakh and English. The owner’s Premium UI 2.0 brief is the visual reference: violet, gold,
illustrated services and rounded surfaces. Existing Food/Grocery and booking DEV behavior remains authoritative;
see docs/product/food-mvp.md and docs/product/booking-mvp.md.

## Visual direction
Brand violet #7055F5, light canvas #F8F9FC, dark canvas #101426,
white surface #FFFFFF, accent gold #F2C77D and light ink #172033.
Consumer starts in light mode and stores the selected theme on the device.
Violet mountain and assistant surfaces, illustrated categories and Food
photography anchor the home screen. The assistant has an explicit unavailable
state while the backend lacks an AI API.

## Typography and layout
Bundled Noto Sans (KundeSans) with Cyrillic/Kazakh coverage; 30/24/20 display,
17/16 body, 10.5–12 compact category/caption text. Wordmark uses heavy weight.
Content max width 600–640 dp, 16–24 dp insets, 16–24 dp radii. Controls have
at least 48 dp touch targets. Five category columns at 360 dp and above;
large text and smaller screens reflow to four/three columns. Content scrolls
naturally within safe areas. Main target widths: Samsung 360/390/412 dp.

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
