Первый этап — KUNDE Product Requirements Document (PRD).

Это главный документ, который объяснит разработчикам, дизайнерам и будущей команде, что именно мы создаём, как это должно работать и каким должен быть результат.

Я предлагаю сразу проектировать полную экосистему KUNDE, но чётко разделить:
- что обязательно для первого запуска;
- что появится в следующих релизах;
- что закладывается в архитектуру с самого начала.
KUNDE
Product Requirements Document

Документ № 01 · Версия 1.0 · 10 ноября 2026

Продукт

KUNDE Super App

Первый рынок

Алматы, Казахстан

Стратегия

Full Vision / Phased Launch

AI

AI-native architecture

Языки запуска

Қазақша / Русский

# KUNDE — Product Requirements Document (PRD)

**Version:** 1.0  
**Date:** November 10, 2026  
**Product:** KUNDE Super App  
**Tagline:** Everyday, made easier.  
**Initial Market:** Almaty, Kazakhstan  
**Product Strategy:** Full Product Vision, Phased Execution  
**AI Strategy:** AI-native foundation from day one

---

# 1. Product Vision

## 1.1. What is KUNDE?

KUNDE is an AI-native everyday-life Super App that brings essential services, shopping, mobility, bookings, family activities, and personal assistance together in one unified digital ecosystem.

KUNDE enables people to discover, compare, order, book, pay for, and manage everyday services through one application.

The product must provide a consistent experience across all service categories, with one account, one search experience, one activity center, one payment experience, and one intelligent assistant.

## 1.2. Mission

Make everyday life easier, more convenient, and more organized.

## 1.3. Vision

Become the everyday digital companion people rely on to organize and manage their lives.

## 1.4. Core Value Proposition

- Find what you need.
- Compare available options.
- Book or order in a few steps.
- Manage everything in one place.
- Receive intelligent recommendations.
- Delegate everyday tasks to KUNDE AI.

## 1.5. Product Principles

1. One App, One Account.
2. One Unified Search.
3. One Activity Center.
4. AI at the Core.
5. Local First, Global Ready.
6. Trust and Safety by Design.
7. Consistent Experience Across Categories.
8. Quality Over Quantity.
9. Transparent Pricing.
10. User Control and Consent.

# 2. Target Users

## 2.1. Consumer

People who need convenient access to everyday services.

Needs:
- Find nearby services.
- Compare prices and ratings.
- Book appointments.
- Order products and food.
- Arrange transportation and delivery.
- Track active orders.
- Manage family activities.
- Receive useful reminders.

## 2.2. Families

People coordinating tasks and services for family members.

Needs:
- Manage family-related bookings.
- Maintain separate profiles and permissions.
- Organize children's activities.
- Coordinate appointments and schedules.
- Share selected addresses and plans.

Family members must have separate privacy and authorization settings.

## 2.3. Business Partners

Businesses offering services or products through KUNDE.

Needs:
- Manage business information.
- Create service and product catalogs.
- Manage employees.
- Configure prices and availability.
- Receive and process orders.
- Manage bookings.
- Track payments and settlements.
- Review performance analytics.

## 2.4. Service Providers and Drivers

Independent providers and operational personnel.

Needs:
- Receive assignments.
- Accept or reject eligible tasks.
- Navigate to destinations.
- Update task status.
- Track earnings.
- Communicate with customers where permitted.

## 2.5. Platform Operations

Internal KUNDE employees responsible for platform quality.

Needs:
- Manage users and partners.
- Moderate listings.
- Monitor transactions.
- Resolve disputes.
- Manage refunds and cancellations.
- Investigate fraud.
- Monitor platform performance.

# 3. Product Ecosystem

KUNDE consists of four primary applications or interfaces.

1. KUNDE Consumer — customer mobile application.
2. KUNDE Partner — business management interface.
3. KUNDE Driver / Provider — service fulfillment interface.
4. KUNDE Admin — internal management platform.

All interfaces use shared platform capabilities and consistent domain contracts.

The initial development priority is the Consumer application and the minimum operational functionality required to support it.

# 4. Consumer Application

## 4.1. Main Navigation

The consumer application must have five primary navigation destinations.

### Home
- Personalized home screen.
- Location selector.
- Search.
- AI Assistant entry point.
- Service category shortcuts.
- Popular services.
- Nearby businesses.
- Current orders and bookings.
- Relevant promotions.
- Recommended services.

### Explore
- All available categories.
- Category-specific browsing.
- Nearby businesses.
- Search and filters.
- Sorting.
- Business and service details.

### AI
- AI conversation interface.
- Text input.
- Voice input when supported.
- Suggested prompts.
- Task planning.
- Search and comparison.
- Review of proposed actions.
- Task execution with appropriate authorization.

### Activity
- Active orders.
- Upcoming bookings.
- Completed orders.
- Cancellations.
- Payment history.
- Order details.
- Receipts.
- Support requests.

### Profile
- Personal information.
- Addresses.
- Payment methods.
- Language.
- Notifications.
- Family profiles.
- Favorites.
- Security.
- Privacy.
- Help and support.

# 5. Service Categories

KUNDE must support eight major categories.

## 5.1. Mobility

Services:
- Taxi.
- Intercity transportation.
- Courier delivery.
- Parcel delivery.
- Freight transportation.
- Car rental.
- Scheduled transportation.

Core functionality:
- Pickup and destination selection.
- Route visualization.
- Fare estimation.
- Vehicle or service selection.
- Booking.
- Driver assignment.
- Live tracking where supported.
- Trip completion.
- Payment.
- Ratings.

## 5.2. Food & Shopping

Services:
- Restaurants.
- Cafes.
- Grocery stores.
- Supermarkets.
- Fruit and vegetable shops.
- Flowers.
- Gifts.
- Ready-made meals.
- Retail products.

Core functionality:
- Product and menu catalogs.
- Categories and search.
- Shopping cart.
- Modifiers and product options.
- Availability.
- Delivery or pickup.
- Order tracking.
- Reordering.
- Refund and cancellation workflows.

## 5.3. Home

Services:
- Cleaning.
- Plumbing.
- Electrical work.
- Home repairs.
- Appliance maintenance.
- Furniture assembly.
- Laundry.
- Dry cleaning.
- Moving services.

Core functionality:
- Service descriptions.
- Price models.
- Provider profiles.
- Availability.
- Appointment booking.
- Address selection.
- Service requirements and notes.
- Completion confirmation.
- Ratings and disputes.

## 5.4. Health

Services:
- Clinics.
- Doctors.
- Dentistry.
- Laboratories.
- Online consultations.
- Preventive services.
- Pharmacy discovery and permitted purchases.

Core functionality:
- Provider discovery.
- Doctor profiles.
- Appointment availability.
- Booking.
- Appointment reminders.
- Cancellation and rescheduling.
- Relevant service information.

Health data must be handled as sensitive information. KUNDE AI must not independently diagnose conditions or replace qualified medical professionals.

Regulated services and pharmacy functionality require separate legal, compliance, and operational review before launch.

## 5.5. Personal Care

Services:
- Beauty salons.
- Barbershops.
- Nail studios.
- Cosmetology.
- SPA.
- Massage.
- Fitness.
- Personal trainers.

Core functionality:
- Service catalog.
- Staff selection.
- Price and duration.
- Available time slots.
- Appointment booking.
- Booking management.
- Ratings and reviews.

## 5.6. Family & Education

Services:
- Children's centers.
- Tutors.
- Language schools.
- Courses.
- Sports clubs.
- Educational activities.
- Pet-related services.

Core functionality:
- Family profiles.
- Class schedules.
- Provider discovery.
- Enrollment.
- Booking.
- Reminders.
- Parent-controlled permissions.

## 5.7. Experiences

Services:
- Cinema.
- Concerts.
- Theater.
- Events.
- Tickets.
- Hotels.
- Travel.
- Excursions.
- Entertainment.

Core functionality:
- Event discovery.
- Date and location filters.
- Ticket availability.
- Reservation and payment.
- Booking confirmation.
- Cancellation rules.
- Digital ticket storage where supported.

## 5.8. Auto

Services:
- Car wash.
- Auto service.
- Tire replacement.
- Detailing.
- Oil changes.
- Diagnostics.
- Towing.
- Roadside assistance.

Core functionality:
- Service discovery.
- Vehicle profile.
- Service selection.
- Price estimates.
- Appointment booking.
- Provider location.
- Booking history.

# 6. Shared Platform Capabilities

The following capabilities must work consistently across service categories.

## 6.1. Unified Identity

- One consumer account.
- Secure authentication.
- Phone-based registration.
- OTP verification.
- Session management.
- Device management.
- Account recovery.
- Optional biometric authentication.
- Profile management.

Authentication providers must be abstracted so that SMS, messaging providers, and alternative methods can be changed without redesigning the application.

## 6.2. Unified Search

Search across:
- Businesses.
- Products.
- Services.
- Categories.
- Events.
- Locations.

Search capabilities:
- Text search.
- Location-based search.
- Category filters.
- Price filters.
- Ratings.
- Availability.
- Sorting.
- Recent searches.
- Suggestions.
- Typo tolerance where supported.

## 6.3. Location

- Current location with permission.
- Manual address selection.
- Saved addresses.
- Map selection.
- Address autocomplete where supported.
- Service coverage validation.
- Distance calculations.
- Geospatial search.

Location access must be optional unless necessary for a particular requested service.

## 6.4. Orders and Bookings

Support two fundamental transaction models.

**Order:** a purchase or fulfillment request, such as food, groceries, or delivery.

**Booking:** a reservation for a future service, time slot, appointment, or event.

Each transaction must have:
- Unique identifier.
- Customer.
- Provider or merchant.
- Service or product details.
- Price breakdown.
- Status history.
- Payment state.
- Cancellation policy.
- Timestamps.
- Support and dispute context.

## 6.5. Payments

- Payment method management.
- Payment initiation.
- Payment confirmation.
- Refunds.
- Transaction history.
- Receipts.
- Provider settlement records.
- Commission accounting.
- Reconciliation.

Payment providers must be integrated through an abstraction layer.

Sensitive card information must not be stored directly by KUNDE unless explicitly permitted and appropriately certified.

## 6.6. Notifications

Channels:
- Push notifications.
- In-app notifications.
- SMS where required.
- Email where appropriate.

Notification categories:
- Authentication and security.
- Order updates.
- Booking reminders.
- Payments.
- Refunds.
- Support.
- Promotions.
- AI task updates.

Users must control non-essential notification preferences.

## 6.7. Favorites

Users can save:
- Businesses.
- Services.
- Products.
- Providers.
- Locations.
- Events.

## 6.8. Reviews and Ratings

- Customer ratings.
- Written reviews.
- Verified transaction association.
- Moderation.
- Reporting.
- Provider responses where supported.

## 6.9. Customer Support

- Help center.
- Support requests.
- Order-specific support.
- Complaint submission.
- Dispute management.
- Refund requests.
- Support history.

# 7. KUNDE AI

## 7.1. AI Product Vision

KUNDE AI is a personal everyday-life assistant capable of understanding requests, finding relevant services, planning multi-step tasks, and executing authorized actions through KUNDE platform capabilities.

It must be more than a chatbot.

## 7.2. AI Capabilities

Initial:
- Natural language understanding.
- Context-aware recommendations.
- Search assistance.
- Service comparisons.
- FAQ and help.
- Request clarification.

Intermediate:
- Multi-step task planning.
- Availability checking.
- Booking preparation.
- Shopping list creation.
- Order preparation.
- Schedule coordination.

Advanced:
- Authorized task execution.
- Cross-category planning.
- Personalized recommendations.
- Family task coordination.
- Proactive reminders.
- Long-term preference management with user controls.

## 7.3. AI Safety and Authorization

AI must:
- Clearly distinguish suggestions from confirmed actions.
- Request confirmation before paid actions.
- Never independently transfer money.
- Respect user permissions.
- Respect family profile boundaries.
- Avoid unauthorized disclosure of sensitive data.
- Keep an auditable record of actions.
- Handle failed and partially completed tasks.
- Explain uncertainty and unavailable services.

## 7.4. AI Architecture Requirements

The architecture must include:
- AI orchestration layer.
- Model provider abstraction.
- Tool registry.
- Permission and authorization checks.
- Context management.
- Conversation history controls.
- User preference storage.
- Task state management.
- Execution monitoring.
- Cost and usage monitoring.
- Safety and policy enforcement.

The platform must not depend on one specific AI model provider.

# 8. Partner Platform

Partners must be able to:

- Register a business.
- Submit verification information.
- Manage business profiles.
- Manage locations.
- Configure categories.
- Create services and products.
- Set prices.
- Configure schedules.
- Manage employees.
- Receive bookings and orders.
- Accept or reject eligible requests.
- Update fulfillment status.
- Review transactions.
- Track settlements.
- View analytics.
- Contact support.

Partner permissions must support business owners, managers, employees, and other authorized roles.

# 9. Driver / Provider Platform

The provider interface must support:

- Secure registration.
- Identity and eligibility verification where required.
- Availability status.
- Assignment notifications.
- Task acceptance.
- Navigation.
- Task status updates.
- Customer communication through controlled channels.
- Earnings.
- Payout history.
- Support and incident reporting.

Provider capabilities may vary by service category.

# 10. Admin Platform

KUNDE Admin must provide:

- User management.
- Partner management.
- Provider management.
- Category management.
- Catalog moderation.
- Order monitoring.
- Booking monitoring.
- Payment and refund operations.
- Commission management.
- Promotion management.
- Review moderation.
- Dispute management.
- Support management.
- Fraud monitoring.
- AI usage monitoring.
- System health monitoring.
- Audit logs.
- Business analytics.

Administrative actions must be permission-controlled and auditable.

# 11. MVP Scope — Almaty

The first public version must focus on a limited number of high-frequency services.

Proposed MVP:
- Registration and authentication.
- User profile.
- Address management.
- Home screen.
- Unified search.
- Restaurants and food ordering.
- Grocery ordering where merchant operations are ready.
- Mobility and/or courier services through available operational integrations.
- Merchant and provider onboarding sufficient for MVP operations.
- Orders and tracking.
- Payments.
- Notifications.
- Ratings.
- Customer support.
- Basic KUNDE AI search and recommendations.
- Admin operations.

The MVP must not pretend to support a service category when its supply, fulfillment, payment, and support processes are not operational.

# 12. Release Strategy

Phase 0 — Product and Technical Foundation:
- Product specification.
- UX/UI system.
- Architecture.
- Security model.
- Identity foundation.
- Search and location foundation.
- AI foundation.
- Core platform contracts.

Phase 1 — Almaty MVP:
- Initial consumer experience.
- Food and grocery.
- Selected mobility and delivery capabilities.
- Core order and payment workflows.

Phase 2 — Everyday Services:
- Home.
- Personal Care.
- Auto.
- Advanced bookings.

Phase 3 — Family & Lifestyle:
- Family.
- Education.
- Health.
- Experiences.

Phase 4 — AI Life Assistant:
- Multi-step task orchestration.
- Authorized execution.
- Personalization.
- Proactive assistance.

Phase 5 — Kazakhstan Expansion:
- Additional cities.
- Local partners.
- Operational scaling.

Phase 6 — International Expansion:
- Regional localization.
- Local payment providers.
- Regulatory adaptation.
- International partnerships.

# 13. Non-Functional Requirements

## Security
- Encryption in transit and at rest.
- Secure authentication.
- Role-based access control.
- Least-privilege access.
- Audit logging.
- Secure secret management.
- Protection against common application vulnerabilities.
- Abuse and fraud controls.

## Performance
- Fast initial application loading.
- Responsive navigation.
- Efficient search.
- Reliable order status updates.
- Optimized image delivery.
- Graceful handling of network failures.

Quantitative latency and throughput targets must be defined after workload estimation and technical architecture design.

## Reliability
- Monitoring and alerting.
- Error tracking.
- Retry policies.
- Idempotent operations.
- Backup and recovery.
- Graceful degradation.
- Payment reconciliation.

## Scalability
- Multi-city support.
- Multi-region readiness.
- Horizontal scaling where appropriate.
- Asynchronous processing for suitable workflows.
- Clear domain boundaries.
- Integration isolation.

## Localization
- Kazakh.
- Russian.
- English.
- Additional languages through localization resources, not hardcoded UI strings.

## Accessibility
- Readable typography.
- Adequate color contrast.
- Screen reader support.
- Accessible controls.
- Clear error messages.
- Support for dynamic text sizes.

# 14. Analytics and KPIs

Product metrics:
- DAU.
- MAU.
- D7 retention.
- D30 retention.
- Orders per active user.
- Repeat purchase rate.
- Cross-category adoption.
- Search-to-order conversion.
- Booking conversion.

Operational metrics:
- Fulfillment rate.
- Cancellation rate.
- On-time completion.
- Refund rate.
- Support resolution time.
- Partner activation.
- Provider availability.

Financial metrics:
- Gross merchandise value.
- Revenue.
- Commission revenue.
- Contribution margin.
- Customer acquisition cost.
- Customer lifetime value.
- Payment failure rate.

AI metrics:
- Task completion rate.
- Tool execution success.
- User confirmation rate.
- Failed task rate.
- AI response latency.
- Cost per completed task.
- User satisfaction.

All metrics must be defined consistently before being used for executive reporting.

# 15. Privacy and Compliance

KUNDE must conduct a legal and compliance review before launching regulated services.

The product must support:
- Explicit user consent.
- Privacy settings.
- Data access controls.
- Data retention policies.
- Account deletion workflows.
- Sensitive data separation.
- Auditability.
- Regional data protection requirements.
- Payment compliance requirements.
- Special controls for children's and health-related data.

# 16. Out of Scope for Initial MVP

Unless required for a specific launch partnership, the following are not initial MVP priorities:

- Full international launch.
- Autonomous AI payments.
- Fully autonomous AI personal agent.
- All eight categories at launch.
- Complex loyalty marketplace.
- Financial products and lending.
- Social network functionality.
- Cryptocurrency and digital assets.
- Unverified medical decision support.

These may be evaluated separately in future product strategy.

# 17. Definition of MVP Success

The MVP is ready for public launch when:

1. Users can securely register and manage accounts.
2. Users can discover real available services.
3. Users can complete supported orders or bookings.
4. Payments and refunds work reliably.
5. Partners can process transactions.
6. Users can track transaction status.
7. Support can resolve issues.
8. Administrative operations are functional.
9. Critical security and privacy requirements are met.
10. Monitoring and incident response are operational.
11. The platform can measure user, operational, and financial outcomes.

# 18. Product Governance

This PRD is the central product requirements baseline.

Every new feature must:
- Have a defined user problem.
- Belong to a product domain.
- Have clear business rules.
- Define permissions and data access.
- Define success criteria.
- Include failure and cancellation scenarios.
- Have acceptance criteria.
- Be evaluated against the phased roadmap.

Changes to the product vision, core domain boundaries, payments, identity, privacy, and AI authorization must be reflected in the relevant specifications.

---

**End of PRD 1.0 — KUNDE Super App**

Что делаем дальше
PRD 1.0 задаёт общую основу. Но перед тем как передавать его разработчикам, необходимо детализировать самые важные пользовательские сценарии: например, регистрацию, поиск, оформление заказа, бронирование, оплату, возврат, поддержку и работу AI.