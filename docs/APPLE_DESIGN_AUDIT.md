# Apple design audit — October 2026

Scope: onboarding, invites, settings, purchases, account/error recovery, accessibility, and navigation outside the active home/Super Psst implementation. Reviewed `CLAUDE.md`, `DESIGN.md`, `docs/FEATURE_RELEASE.md`, SwiftUI source, and screenshots in `output/feature-review`. Apple guidance checked 11 October 2026. Findings distinguish visible evidence from source-level behavior that needs a device check.

## Findings

### P1 — Invite cancellation can look successful while leaving the invite usable (addressed)

**Evidence:** `Psst/Live/SettingsSheet.swift:223-229` immediately removes the open-invite row, swallows revoke failure, and only replaces the list if a refresh succeeds. If cancellation and refresh both fail, the invite disappears from the UI while remaining usable on the server. Unblock similarly swallows failure at `232-236`.

**User consequence:** A person may believe an invite sent to the wrong person was cancelled when its link/code remains usable. The unblock path has the same silent-failure risk but lower immediate impact.

**Fix:** Keep the row until server confirmation, or restore it on failure and show a concise inline error with a retry path. Also expose unblock failures and retain the blocked row. Test with network loss after tapping and a server error.

**Resolution (implemented):** Settings keeps open invites and blocked people visible until the corresponding server mutation succeeds. Failures keep the row and show an inline retry instruction; Cancel/Unblock disable only for that row while pending. Failed cancellation explicitly says the invite may still work. Regression tests exercise failure, retry, waiting for confirmation, and overlapping cancellation.

**Basis:** Apple’s interface guidance recommends useful, actionable error messages and accurate interface copy: [Writing](https://developer.apple.com/design/human-interface-guidelines/writing).

### P2 — Rename failure message blames the name when the request may have failed (addressed)

**Evidence:** `Psst/Live/SettingsSheet.swift:210-219` does show an inline message after failure, but reports every request error as “Names can be 1 to 40 characters,” although the API may fail for connectivity/server reasons. The field is cleared only on success. In initial onboarding, failures also show an inline error at `Psst/Live/OnboardingViews.swift:38-43,107-120`.

**User consequence:** A person changing their name while offline may be told to shorten a valid name. The failure is visible, but the explanation is misleading and does not offer a retry cue.

**Fix:** Validate the 1–40 character range locally and show a distinct connectivity/general-save message for request failures; preserve the current text and expose the message to VoiceOver. Verify offline and server rejection paths.

**Resolution (implemented):** Names are trimmed and validated locally before requesting a save. Offline and other request failures have distinct, truthful inline messages. The draft stays in the field on failure; Save and keyboard submission share an in-flight guard. Successful requests clear only the unchanged submitted draft. Regression tests distinguish invalid length, offline, server rejection and successful retry.

**Basis:** Apple says to show errors next to the field and explain how to correct them, rather than using robotic or misleading errors: [Writing](https://developer.apple.com/design/human-interface-guidelines/writing).

### P2 — Invite handlers lack re-entry guards for non-button activation paths (addressed)

**Evidence:** The visible code-check button passes `isChecking` as `busy` and `whiteBand` disables its button while busy (`InviteSheet.swift:210-234`); retry appears only after the error state and clears it before starting. However, `check()` (`248-262`) and `create()` (`158-172`) have no handler-level `guard` against an already-running task. Keyboard submission calls `check()` directly (`183-190`), so a second submit or queued activation could overlap even while the button is disabled. The screenshot does not establish that this occurs in practice.

**User consequence:** If a second keyboard submit or queued activation enters during a slow request, duplicate preview/create requests could overlap and make the final state harder to reason about. This is a lower-confidence robustness risk than a visible tap issue.

**Fix:** Add handler-level guards for `isChecking` and `isCreating` (and consider `isAccepting`), retain the visible disabled/progress states, then verify keyboard submit during a deliberately delayed request.

**Resolution (implemented):** Create, Check and Accept now guard against re-entry at their handlers; code entry disables during Check/Accept to keep the reviewed code stable. Existing progress/disabled controls remain. Acceptance errors also render independently of a pending invite preview, so a failed connection request remains visible beside the retry action. A deliberately delayed keyboard-submission device check is still required.

**Basis:** Apple recommends a visible press state and clear, recognizable button behavior: [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons).

### P2 — Invite code field scaling (addressed during final QA)

**Original evidence:** `Psst/Live/InviteSheet.swift:183-193` applied `.minimumScaleFactor(0.5)` to a 40pt scaled code field. The branch scrolls only when `dynamicTypeSize.isAccessibilitySize` (`29-35`), but the field still compresses horizontally rather than allowing the code to wrap/read at the chosen size.

**User consequence:** A person who enlarged text to read comfortably can get a much smaller code entry field precisely in a core connection flow. Typing remains possible, but the visual cue and entered characters may be hard to inspect.

**Fix:** Keep the monospaced field at its scaled size, provide enough vertical room and wrapping/scrolling, and group the code visually as the app already does for share output. Verify AX sizes and a narrow iPhone.

**Resolution:** Final QA removed the scale-down modifier and uses a semantic monospaced title style for entry. Accessibility-size output codes already wrap into two groups. A focused native capture checks the revised entry.

**Basis:** Apple advises adapting layouts for Dynamic Type and allowing adjacent content to reflow: [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout).

### P2 — “Coming” widget is presented as an included Psst+ perk (addressed)

**Evidence:** `Psst/Live/PsstPlusSheet.swift:29-35` lists “Home-screen widget (coming)” in the same list as current benefits; owner-approved release behavior says widget is later and the current unlock covers personal extras.

**User consequence:** A buyer could interpret a future feature as part of the current purchase and make a purchase decision on an unavailable capability.

**Fix:** Remove it from the purchase benefits until available, or place it in a clearly separate “Planned” note outside the purchasable-value list. Verify StoreKit product copy and paywall on device before release.

**Resolution (implemented):** Removed the unavailable widget from the purchasable benefits. Current Psst+ perks remain unchanged. StoreKit product metadata and on-device purchases still need release validation.

**Basis:** Apple’s in-app purchase guidance recommends simple, clear product names and descriptions so people can understand what they are buying: [Apple In-App Purchase HIG](https://developer.apple.com/design/human-interface-guidelines/apple-in-app-purchase). Apple’s product metadata guidance also calls for clear, descriptive names and text: [Creating SKUs for In-App Purchases](https://developer.apple.com/documentation/advancedcommerceapi/creating-your-purchases).

### P2 — App icon change errors are silently discarded (addressed)

**Evidence:** `Psst/Live/PsstPlusSheet.swift:120-123` updates state only when `setAlternateIconName` succeeds and ignores the error otherwise.

**User consequence:** Selecting an icon may appear to do nothing, with no explanation or retry guidance.

**Fix:** Surface a short inline error and preserve the currently selected checkmark; provide a retry through selecting again. Device-check the system confirmation and failure callback.

**Resolution (implemented):** Icon choices disable while the system request is pending. Failure shows an inline retry message and preserves the selected checkmark. Success reads the actual system icon selection on the main actor. System confirmation/error callbacks still need a physical-device check.

**Basis:** Apple’s [Writing](https://developer.apple.com/design/human-interface-guidelines/writing) guidance recommends helpful, actionable error feedback.

### P2 — Small white subtitles on the gold invite band need more contrast (addressed)

**Evidence:** The gold token is `#B87500` in `Psst/DesignTokens.swift`; the invite chooser uses white, medium-weight subheadline text on it in `Psst/Live/InviteSheet.swift`. Calculating relative sRGB luminance gives **3.76:1** for white on this gold. This is below Apple's 4.5:1 guidance for text up to 17pt at ordinary sizes. The default-size native invite screenshot shows this combination. This finding was added by the parent during final visual verification.

**User consequence:** Small subtitles and expiry information on gold are harder to read at ordinary text sizes, particularly with low vision or poor lighting.

**Fix:** Preserve the approved gold direction while using a darker background or darker subtitle ink. At minimum, provide a higher-contrast color variant when Increase Contrast is enabled, as Apple permits when the default scheme misses the minimum. Verify default and increased-contrast appearances with Accessibility Inspector.

**Resolution (implemented):** The invite chooser and share-code band use a dedicated darker gold `#A66700`, with calculated white-text contrast **4.60:1**, including ordinary-size subtitles and expiry text. The home gold band keeps its approved color. Verify actual rendering with Accessibility Inspector.

**Basis:** [Apple HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) specifies contrast guidance and system-setting alternatives. The rejected header placement has since been replaced by a per-person placement proposal.

### P3 — Notification opt-in rationale is a question, not a direct explanation (addressed)

**Evidence:** `Psst/Live/OnboardingViews.swift:162-185` asks “Get a notification when someone taps you?” with “Yes, notify me” / “Not now.” The context is clear and the choice is balanced, but the screen does not state that notifications are the way to notice incoming Pssts while away; that consequence appears only in the “Not now” accessibility hint and settings copy.

**User consequence:** People may consent without knowing the practical benefit, or decline without understanding in-app delivery remains available. This is a refinement, not a blocker.

**Fix:** Add one plain sentence under the question explaining the benefit and the in-app alternative, keeping a single button that opens the system alert plus an explicit “Not now” choice. Check screen-reader order and the actual iOS permission sheet.

**Resolution (implemented):** Added “Know when a Psst arrives. You can also see Pssts when you open the app.” below the question. The explicit Not now choice remains; both choices prevent overlapping activation while the system request is pending. VoiceOver order and system permission presentation still need a device check.

**Basis:** The Apple HIG page exists at [Managing notifications](https://developer.apple.com/design/human-interface-guidelines/managing-notifications); Apple’s guidance says to explain the reason before asking and give a clear opt-in/out choice. The linked [Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy/) guidance also supports contextual pre-alert explanations.

## Observed captures

The available captures are simulator/test screenshots, not a current physical-device review. `features-03-invite.png` shows the chooser: large bands have strong hierarchy, readable subtitles, and a clear Cancel control. `features-07-settings.png` shows settings through People at default text size; grouped rows are legible, but the screen is long, so accessibility-size scrolling and focus order need a live check. The Super screenshot has since been refreshed with the owner-approved minimal copy. Native captures are refreshed after implementation; they remain simulator fixtures.

## Device checks still needed

These are code-based risks, not confirmed visual defects: AX5/Dynamic Type and VoiceOver focus order across onboarding/invite/settings; keyboard plus safe-area behavior on compact devices and landscape; slow/offline operation for invite, rename, unblock/revoke, icon selection, and StoreKit restoration; notification opt-in after the system sheet returns; and whether the current screenshots match latest source. Apple’s layout and accessibility guidance calls for checking size variations and Dynamic Type on actual layouts: [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).

## Final QA additions

Largest-text native captures confirmed that the activity segmented tabs retained
small text while the surrounding UI scaled. The new activity view now uses
readable inline choices at accessibility sizes, while ordinary sizes retain
the approved segmented layout. The code-entry scaling issue above was also
addressed. A different implementation agent addressed the remaining findings at the owner's request. Automated settings recovery checks and native build validation are recorded below; device checks remain explicitly listed above.

## Follow-up validation

- Four settings regression tests cover failed cancellation and retry, confirmation before removal and duplicate suppression, failed unblock and retry, and invalid/offline/server-rejected/successful name saves.
- Gold contrast calculated from linearized sRGB relative luminance: white on `#A66700` is 4.60:1.
- Native iOS unit tests: **59 passed**, zero failures, including the four new recovery regressions. Result bundle: `/tmp/psst-audit-fixes-tests.xcresult`; log: `/tmp/psst-audit-fixes-tests.log`.
- No production deployment, App Store purchase, or physical-device permission/icon callback test was performed.

- Error-feedback follow-up: acceptance failures remain visible even when the invite preview is still pending. This final rendering change is included in the parent's next native UI build/capture; it was not part of the earlier 59-test run.
