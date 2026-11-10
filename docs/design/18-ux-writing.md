# 18 — UX Writing

## Voice rules

Be warm, direct, brief and specific. Put outcome first, then reason, then next step. Use active verbs (“Choose an address”, “Review total”). Say “We’re checking” for unknown external status; never say payment/order is complete unless verified. Explain estimates and policy before confirmation. Avoid blame, internal jargon, false urgency, “AI magic”, exclamation overload and vague “Something went wrong”.

## Component copy patterns

| Context | Pattern | Example (English source) |
|---|---|---|
| Button | Verb + object | “Choose a time”, “Review order”, “Try again” |
| Label | Name the value | “Delivery address”, “Appointment time” |
| Placeholder | Example, not label | “Search services or businesses” |
| Empty | What + why + next action | “No orders yet. Your orders will appear here. Explore services.” |
| Error | What failed + safe recovery | “We couldn’t load results. Check your connection and try again.” |
| Payment pending | Uncertainty + avoid duplicate | “We’re checking your payment. Please don’t pay again yet.” |
| Confirmation | Exact consequence | “Cancel this booking? Any cancellation fee will be shown before you confirm.” |
| Refund | Verified state + timing only if known | “Refund requested. We’ll update this page when it’s confirmed.” |
| AI | Distinguish proposal from execution | “I found three options. I haven’t booked anything.” |
| Support | Respectful, nonjudgmental | “Tell us what happened. We’ll attach this order to your request.” |

## Sample localized strings

These are draft translations and require native-language review before release.

| Key / meaning | Қазақша draft | Русский | English |
|---|---|---|---|
| `home.search` — What are you looking for? | Не іздеп жүрсіз? | Что вы ищете? | What are you looking for? |
| `common.continue` — Continue | Жалғастыру | Продолжить | Continue |
| `search.empty` — No results | Нәтиже табылмады | Ничего не найдено | No results found |
| `payment.pending.no_retry` | Төлемді тексеріп жатырмыз. Қайта төлем жасамаңыз. | Проверяем платёж. Пока не оплачивайте повторно. | We’re checking your payment. Please don’t pay again yet. |
| `booking.slot.expired` | Бұл уақыт енді қолжетімсіз. Басқа уақытты таңдаңыз. | Это время уже недоступно. Выберите другое. | This time is no longer available. Choose another. |
| `order.cancelled` | Тапсырыс тоқтатылды. Қайтарым мәртебесін осы жерден көре аласыз. | Заказ отменён. Статус возврата можно посмотреть здесь. | Order cancelled. You can check the refund status here. |
| `ai.not_booked` | Мен әлі ештеңе брондаған жоқпын. | Я пока ничего не забронировал. | I haven’t booked anything yet. |

## Numbers, names and accessibility

Do not put currency symbol alone when ambiguity exists; use locale-aware amount + code. Read status as plain language. Preserve business/provider names as supplied, with transliteration only when approved. Avoid abbreviations in buttons. Error copy is announced with relevant field/heading; one error summary is not repeated verbatim on every field. Legal/financial statements are reviewed by product/legal translators, not generated at runtime by AI.
