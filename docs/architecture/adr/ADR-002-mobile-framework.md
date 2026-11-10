# ADR-002: Consumer Mobile Framework

- **Status:** Proposed for review
- **Context/problem:** Consumer experience targets iOS and Android; localization/accessibility and iteration speed matter.
- **Options:** Flutter; React Native; native Swift/Kotlin.
- **Evaluation:** Flutter offers consistent shared UI and one feature team; plugin/platform expertise needed. React Native aligns with TypeScript web ecosystem but depends on native-module compatibility. Native offers strongest platform fit but duplicates delivery and cost.
- **Decision:** Recommend Flutter for consumer app; partner/admin surface can be web, provider client chosen from workflow research.
- **Consequences:** Dart expertise, plugin security/lifecycle governance, platform-specific testing remain necessary.
- **Risks:** Team skills unknown; critical SDK may lack robust Flutter integration.
- **Revisit when:** Platform-specific feature/performance or hiring/maintainability evidence materially favors alternative.
