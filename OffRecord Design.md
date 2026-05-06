---
version: "alpha"
name: "OffRecord Pastel Private Journal"
description: "A warm, pastel, premium iOS design system for OffRecord AI Journal — a free, private, on-device voice journal with Friday as the AI companion."
colors:
  primary: "#342044"
  secondary: "#7FA08A"
  tertiary: "#BBA7E8"
  neutral: "#FFF8F0"

  brand-plum: "#342044"
  brand-sage: "#7FA08A"
  brand-sage-dark: "#5F806B"
  brand-lavender: "#BBA7E8"
  brand-lavender-dark: "#7B5CAF"
  brand-peach: "#F6B98F"
  brand-blush: "#F6A9B8"
  brand-mint: "#A8D8BE"
  brand-aqua: "#6FC6B8"
  brand-sky: "#A8D6F0"
  brand-yellow: "#F7D98B"
  brand-coral: "#EF8A7A"

  bg-primary: "#FFF8F0"
  bg-secondary: "#F7F1EA"
  bg-lavender-tint: "#F4EEFF"
  bg-blush-tint: "#FFF0F3"
  bg-sage-tint: "#EEF6EF"
  bg-peach-tint: "#FFF1E5"
  bg-sky-tint: "#EEF8FF"
  bg-elevated: "#FFFFFF"

  surface-primary: "#FFFFFF"
  surface-warm: "#FFFBF7"
  surface-peach: "#FFF1E5"
  surface-blush: "#FFF0F3"
  surface-lavender: "#F4EEFF"
  surface-sage: "#EEF6EF"
  surface-mint: "#EFFAF4"
  surface-blue: "#EEF8FF"

  text-primary: "#18131D"
  text-heading: "#241730"
  text-brand: "#342044"
  text-secondary: "#716A75"
  text-tertiary: "#9B949E"
  text-inverse: "#FFFFFF"
  text-sage: "#5F806B"
  text-warm: "#C97836"

  border-soft: "#EEE7EF"
  border-warm: "#F2E2D5"
  border-sage: "#D8E6DC"
  divider: "#E8E1E8"
  hairline: "#F0ECF1"

  mood-great: "#A8D8BE"
  mood-good: "#7FA08A"
  mood-calm: "#6FC6B8"
  mood-okay: "#F7D98B"
  mood-tired: "#F6B98F"
  mood-sad: "#F6A9B8"
  mood-anxious: "#BBA7E8"
  mood-angry: "#EF8A7A"

typography:
  display-xl:
    fontFamily: "New York, Georgia, serif"
    fontSize: "52px"
    fontWeight: "700"
    lineHeight: "58px"
    letterSpacing: "-0.04em"
  screen-title:
    fontFamily: "SF Pro Display"
    fontSize: "40px"
    fontWeight: "800"
    lineHeight: "46px"
    letterSpacing: "-0.035em"
  title-lg:
    fontFamily: "SF Pro Display"
    fontSize: "28px"
    fontWeight: "750"
    lineHeight: "34px"
    letterSpacing: "-0.025em"
  title-md:
    fontFamily: "SF Pro Display"
    fontSize: "22px"
    fontWeight: "700"
    lineHeight: "28px"
    letterSpacing: "-0.015em"
  body-lg:
    fontFamily: "SF Pro Text"
    fontSize: "17px"
    fontWeight: "400"
    lineHeight: "25px"
  body-md:
    fontFamily: "SF Pro Text"
    fontSize: "15px"
    fontWeight: "400"
    lineHeight: "22px"
  body-sm:
    fontFamily: "SF Pro Text"
    fontSize: "13px"
    fontWeight: "400"
    lineHeight: "18px"
  label-md:
    fontFamily: "SF Pro Text"
    fontSize: "13px"
    fontWeight: "650"
    lineHeight: "17px"
  label-sm:
    fontFamily: "SF Pro Text"
    fontSize: "11px"
    fontWeight: "650"
    lineHeight: "14px"
    letterSpacing: "0.01em"
  number-lg:
    fontFamily: "SF Pro Rounded"
    fontSize: "44px"
    fontWeight: "800"
    lineHeight: "48px"
    letterSpacing: "-0.035em"

rounded:
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "22px"
  xl: "28px"
  xxl: "34px"
  pill: "999px"

spacing:
  xxs: "2px"
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "20px"
  xxl: "24px"
  xxxl: "32px"
  section: "40px"
  screen-x: "24px"
  screen-y: "28px"

components:
  screen-background:
    backgroundColor: "{colors.bg-primary}"
    textColor: "{colors.text-primary}"
  card-primary:
    backgroundColor: "{colors.surface-primary}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.xl}"
    padding: "20px"
  card-warm:
    backgroundColor: "{colors.surface-warm}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.xl}"
    padding: "20px"
  card-today-moment:
    backgroundColor: "{colors.surface-peach}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.xl}"
    padding: "20px"
  card-ai-insight:
    backgroundColor: "{colors.surface-lavender}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.xl}"
    padding: "18px"
  card-privacy:
    backgroundColor: "{colors.surface-sage}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.lg}"
    padding: "16px"
  button-primary:
    backgroundColor: "{colors.brand-plum}"
    textColor: "{colors.text-inverse}"
    typography: "{typography.label-md}"
    rounded: "{rounded.pill}"
    padding: "16px"
    height: "52px"
  button-friday:
    backgroundColor: "{colors.brand-lavender-dark}"
    textColor: "{colors.text-inverse}"
    typography: "{typography.label-md}"
    rounded: "{rounded.pill}"
    padding: "16px"
    height: "52px"
  button-privacy:
    backgroundColor: "{colors.brand-sage-dark}"
    textColor: "{colors.text-inverse}"
    typography: "{typography.label-md}"
    rounded: "{rounded.pill}"
    padding: "16px"
    height: "52px"
  button-soft:
    backgroundColor: "{colors.bg-lavender-tint}"
    textColor: "{colors.text-brand}"
    typography: "{typography.label-md}"
    rounded: "{rounded.pill}"
    padding: "14px"
  chip-warm:
    backgroundColor: "{colors.bg-peach-tint}"
    textColor: "{colors.text-warm}"
    typography: "{typography.label-sm}"
    rounded: "{rounded.pill}"
    padding: "10px"
  chip-sage:
    backgroundColor: "{colors.bg-sage-tint}"
    textColor: "{colors.text-sage}"
    typography: "{typography.label-sm}"
    rounded: "{rounded.pill}"
    padding: "10px"
  chip-lavender:
    backgroundColor: "{colors.bg-lavender-tint}"
    textColor: "{colors.brand-lavender-dark}"
    typography: "{typography.label-sm}"
    rounded: "{rounded.pill}"
    padding: "10px"
  input-search:
    backgroundColor: "#F0EBF1"
    textColor: "{colors.text-primary}"
    typography: "{typography.body-md}"
    rounded: "{rounded.pill}"
    padding: "14px"
    height: "48px"
  tab-bar:
    backgroundColor: "{colors.surface-primary}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.xxl}"
    padding: "8px"
    height: "76px"
  tab-selected:
    backgroundColor: "#F0EBF1"
    textColor: "{colors.text-brand}"
    typography: "{typography.label-sm}"
    rounded: "{rounded.pill}"
    padding: "10px"
---

## Overview

OffRecord is a private, voice-first AI journal for iPhone and iPad. The visual system must communicate three things immediately: **safety**, **warmth**, and **quiet intelligence**.

The app should feel like a soft private space, not a productivity dashboard. It is intimate enough for late-night voice journaling, polished enough for an App Store feature, and trustworthy enough for a product whose main promise is that the user’s journal stays private and on-device.

Friday is the companion character and the emotional center of the product. She should feel calm, friendly, emotionally intelligent, and non-invasive. Use Friday as a gentle guide, not a mascot that overwhelms the app.

Design keywords:

- Private
- Pastel
- Warm
- Calm
- iOS-native
- Voice-first
- Emotionally intelligent
- Slightly playful
- Premium but approachable
- Local/on-device, not cloud-like or corporate

Primary product surfaces:

- Today: daily entry, voice/write capture, streaks, nudges
- Timeline: searchable journal archive
- Insights: mood, writing, goals, trends, AI summaries
- Friday: private AI assistant, personality patterns, emotions, world model
- Settings: themes, export, iCloud, privacy lock, reminders

## Colors

The palette uses warm cream foundations, white paper-like cards, and pastel accents. Avoid harsh monochrome and saturated startup blues. The product should feel like a private paper journal upgraded with on-device intelligence.

### Foundation

- **Warm Cream (`#FFF8F0`)** is the main background. It gives the app a soft paper-like warmth.
- **Warm White (`#FFFBF7`)** and **White (`#FFFFFF`)** are used for cards and elevated surfaces.
- **Deep Plum (`#342044`)** is the brand anchor. It provides premium contrast without using pure black.
- **Text Black (`#18131D`)** is the default readable body color.

### Semantic Accent Usage

- **Sage (`#7FA08A`)** = privacy, trust, on-device AI, Friday’s safety layer, active Settings state.
- **Lavender (`#BBA7E8`)** = AI, introspection, Friday, personality patterns, soft selected states.
- **Peach (`#F6B98F`)** = journaling warmth, Today moments, streaks, morning/evening ritual.
- **Blush (`#F6A9B8`)** = emotional reflection, care, hearts, vulnerability, compassion.
- **Mint (`#A8D8BE`)** = mood, calm, growth, weekly progress, positive state.
- **Aqua (`#6FC6B8`)** = charts, mood trend lines, progress rings.
- **Sky (`#A8D6F0`)** = export, sync, storage, archive, iCloud-adjacent actions.
- **Yellow (`#F7D98B`)** = gentle neutral mood, highlights, stars, small celebratory details.
- **Coral (`#EF8A7A`)** = warnings, angry mood, destructive confirmation only when softened.

### Gradients

Use gradients sparingly. They should appear in hero cards, Friday glows, capture panels, and App Store marketing art — not everywhere.

Recommended gradients:

- Today capture panel: `#FFE3DD → #F6E8FF`
- Friday CTA: `#BBA7E8 → #D8A6D9`
- App background: `#FFF8F0 → #F8F1F7 → #F3F6EF`
- Friday glow: radial `#FFE6EA → #F4EEFF → transparent`
- AI insight card: `#F4EEFF → #FFF8F0`

### Color Accessibility

Pastel backgrounds should not carry low-contrast pastel text. Use `text-primary`, `text-heading`, or `text-brand` on pastel surfaces. White text is only allowed on dark plum, dark lavender, or dark sage buttons.

## Typography

Use Apple-native typography for app screens. The design should feel native to iOS, not like a web app inside a phone.

### Font Families

- Use **SF Pro Display** for large screen titles and hero labels.
- Use **SF Pro Text** for body copy, metadata, cards, settings, and lists.
- Use **SF Pro Rounded** for friendly metrics, streak numbers, progress values, and mood scores.
- Use **New York / Georgia-style serif** only for marketing posters, landing pages, or the large OffRecord wordmark. Do not use serif fonts heavily inside dense app screens.

### Type Hierarchy

- Screen titles should be large, confident, and tight: 36–40px equivalent.
- Card titles should be 18–22px equivalent with strong weight.
- Body text should remain readable and relaxed: 15–17px equivalent.
- Metadata should be quiet, but never too faint: use `text-tertiary` only for non-critical supporting text.
- Numbers should be rounded and friendly, especially for streaks and goals.

### Voice

Microcopy should be emotionally safe and direct. It should avoid therapy-speak, exaggerated positivity, and judgment.

Good:

- “What do you want to remember?”
- “Write or record”
- “Your journal stays on this device.”
- “Ask Friday what she noticed.”
- “Starting to see patterns.”

Avoid:

- “Unlock your full potential.”
- “Optimize your mental health.”
- “AI-powered transformation.”
- “We know how you feel.”

## Layout

Design for iPhone first, then scale gracefully to iPad. The app should feel spacious even when showing dense personal insights.

### Screen Structure

Use this vertical rhythm:

1. Large title / contextual greeting
2. One hero or summary block
3. One primary action or insight cluster
4. Supporting cards
5. Floating bottom tab bar

Do not stack too many identical white cards. Break density with tinted cards, section labels, illustrations, or compact chart modules.

### Spacing Scale

Use an 8pt rhythm with a few softer in-between values:

- 4px for tiny icon gaps
- 8px for compact internal spacing
- 12px for chip/card internal clusters
- 16px for standard card padding
- 20px for premium card padding
- 24px for screen horizontal padding
- 32px for major section gaps
- 40px for hero-to-content separation

### iPhone Layout Rules

- Horizontal screen padding: 24px.
- Minimum card padding: 16px.
- Preferred card padding: 20px.
- Bottom content should account for floating tab bar height plus safe area.
- Keep primary actions reachable in lower half of screen when possible.
- Use large tap targets: minimum 44px height, preferred 48–56px.

### iPad Layout Rules

- Do not simply stretch iPhone cards edge-to-edge.
- Use a centered readable column for journal content.
- Use two-column layouts for Insights, Settings, and Friday details on wider screens.
- Keep writing and entry detail views calm and focused, with generous margins.

### Screen-Specific Layout Direction

#### Today

Today should feel like the user’s daily ritual. Use a warm hero card for the current moment, then nudges, then a voice/write capture panel. The record action should be visually important but not aggressive.

Core elements to preserve:

- Greeting and date
- Streak / yearly count
- Today’s entry or today’s moment
- Reflection nudges
- Write, record, photo actions
- Privacy reassurance

#### Timeline

Timeline should feel like a memory archive. Use date grouping, highlighted recent entries, search, and quiet metadata. Avoid a plain settings-like list. Use small icons, soft dividers, and differentiated entry cards.

Core elements to preserve:

- Search
- Date groups
- Entry previews
- Word count / time metadata
- Star/favorite indicator where relevant

#### Insights

Insights should be data-rich but calm. Use cards with charts, trend lines, progress rings, and short AI summaries. Never turn this into a cold analytics dashboard.

Core elements to preserve:

- AI insights
- Writing streak
- Weekly goal
- Mood trend
- Writing stats
- Weekly reflection

#### Friday

Friday should feel like a private companion space. Start with the mascot and a compact trust statement, then a clear Talk to Friday CTA, then pattern progress, tabs, and insight cards.

Core elements to preserve:

- Friday mascot
- Talk to Friday CTA
- Pattern progress / data points
- Overview, Personality, Emotions, My World tabs
- Insight cards
- On-device privacy note

#### Settings

Settings should feel trustworthy and readable. Keep privacy and export sections highly legible. Do not over-decorate sensitive controls like Face ID, export, or iCloud Sync.

Core elements to preserve:

- Export controls
- Themes
- Weekly goal
- Privacy lock
- Local AI/offline privacy explanation
- Reminder settings
- Storage
- Optional iCloud Sync

## Elevation & Depth

Use soft paper-like elevation. The interface should feel warm and layered, not glassy or heavy.

Recommended shadow system:

- Cards: black at 6% opacity, blur 18px, y 8px
- Floating controls: black at 8% opacity, blur 24px, y 10px
- Bottom tab bar: black at 10% opacity, blur 30px, y 8px
- Small chips: black at 4% opacity, blur 6px, y 2px

Shadow rules:

- Use broad, low-opacity shadows.
- Avoid hard dark shadows.
- Avoid neumorphism.
- Avoid strong glassmorphism.
- Cards may use a 1px soft border plus subtle shadow.
- Floating tab bar should feel elevated but not oversized.

## Shapes

The shape language is soft, round, and emotionally safe.

### Radius Rules

- Tiny controls: 8–12px radius
- Chips: pill radius
- Small cards: 16px radius
- Primary cards: 22–28px radius
- Large capture panels / bottom sheets: 28–34px radius
- Floating bottom tab bar: 34px or pill radius

### Iconography

Use rounded, friendly icons. Prefer line icons with soft fills for feature callouts. Avoid sharp geometric icons, aggressive security imagery, or enterprise SaaS icon styles.

Icon metaphors:

- Privacy: shield, lock, keyhole, safe leaf
- Voice: microphone, waveform
- Journal: page, pencil, soft notebook
- Friday: sparkle, speech bubble, small avatar
- Mood: face, heart, leaf, weather-like states
- Insights: soft bar chart, trend line, ring
- Export/sync: document, cloud, arrow, archive

### Friday Mascot

Friday is a cute, red-haired chibi assistant. Keep her warm, expressive, and friendly.

Mascot rules:

- Long red-orange hair
- White tee, blue jeans, white sneakers
- Soft blush and friendly eyes
- Use soft pink/lavender glow behind her
- Never make her corporate, robotic, seductive, or hyper-realistic
- Use her sparingly as a companion, not as decoration on every card

## Components

### Cards

Cards are the main structural unit. They should be white or warm-white by default. Use tinted cards for semantic moments.

Card rules:

- Default card background: `surface-primary`
- Preferred radius: `rounded.xl`
- Preferred padding: 20px
- Border: `border-soft` at 1px or 0.5pt
- Shadow: soft card shadow
- Use tinted backgrounds only when they add meaning

Semantic cards:

- Today moment: peach/blush tint
- AI insight: lavender tint
- Privacy: sage tint
- Mood/growth: mint/aqua tint
- Export/sync: sky tint

### Buttons

Primary actions should be calm and clear.

- Use Deep Plum for the strongest universal CTA.
- Use Lavender for Friday / AI chat actions.
- Use Sage for privacy and confirmation actions.
- Use Peach for Today / journaling warmth.
- Use soft buttons for secondary prompts and tabs.

Button rules:

- Height: 48–56px
- Radius: pill
- Text: label-md
- Use icons only when they clarify the action
- Avoid saturated blue CTAs unless referencing App Store / system links

### Chips

Chips are used for streaks, metadata, filters, mood tags, tabs, and pattern states.

Chip rules:

- Use pill radius.
- Use soft tinted backgrounds.
- Keep text short.
- Use semantic colors: peach for streak, sage for privacy, lavender for Friday/AI.
- Do not use too many chip colors in one row.

### Bottom Navigation

The bottom navigation should feel native, floating, and friendly.

Tabs:

- Today
- Timeline
- Insights
- Friday
- Settings

Rules:

- Use a soft white floating pill.
- Selected tab gets a rounded pill background.
- Use semantic active colors per tab.
- Inactive icons use softened black, not gray-blue.
- Labels must remain readable.
- Avoid oversized icons that compete with content.

### Voice Capture Panel

The capture panel is the emotional and functional center of Today.

Rules:

- Use a warm blush-to-lavender gradient.
- Show three clear actions: write, record, photo.
- The microphone can be visually dominant, but not alarm-like.
- Always include privacy reassurance: “Private • On your device” or similar.
- Keep the panel low enough for thumb reach.

### Insight Charts

Charts should be soft and readable.

Rules:

- Use aqua/green for progress and trend lines.
- Use muted gridlines or no gridlines.
- Use emoji/mood dots only when they simplify understanding.
- Prefer rounded bars, soft rings, and simple trend lines.
- Do not use dense analytics visuals.

### Friday Insight Cards

Friday cards should feel like observations, not diagnoses.

Rules:

- Use concise titles: “Who You Are”, “How You Express”, “How You Feel”, “Your World”.
- Include a small semantic icon.
- Keep body copy calm and non-judgmental.
- Use chevrons only when the card opens a deeper page.
- Always keep privacy positioning nearby.

### Settings Controls

Settings must feel clear and trustworthy.

Rules:

- Use grouped cards.
- Use native-looking switches.
- Use sage for enabled privacy or sync states.
- Use clear helper text under sensitive options.
- Do not hide privacy details in tiny text.
- Export actions should use sky/document metaphors.

## Do's and Don'ts

### Do

- Use warm cream backgrounds and paper-like white cards.
- Keep the system pastel, but use high-contrast text.
- Use sage for privacy and trust.
- Use lavender for Friday, AI, and introspection.
- Use peach/blush for journaling warmth and emotional prompts.
- Use mint/aqua for mood, calm, goals, and growth.
- Keep Friday friendly, small, and emotionally safe.
- Make voice capture easy to find.
- Keep privacy reassurance visible across sensitive flows.
- Use AI language carefully: supportive, local, private, non-judgmental.
- Design charts for understanding, not decoration.
- Make the UI feel native to iOS.

### Don't

- Do not copy the existing screenshots exactly; preserve functionality but redesign layout and hierarchy.
- Do not use cold gray as the primary app background.
- Do not use harsh black text when deep plum-black is sufficient.
- Do not place low-contrast pastel text on pastel surfaces.
- Do not make the app feel clinical, medical, or diagnostic.
- Do not make Friday look robotic, corporate, or overly cartoonish.
- Do not overuse gradients.
- Do not use neon colors, harsh blue CTAs, or aggressive shadows.
- Do not imply cloud AI or server processing visually.
- Do not use surveillance-like privacy imagery.
- Do not overcrowd the Insights screen.
- Do not bury export, privacy lock, or iCloud controls.

### Generation Guidance for AI Agents

When generating new OffRecord screens, preserve the product’s core promise: private voice journaling with on-device AI. Every screen should feel calm, soft, readable, and safe.

If choosing between visual delight and trust, choose trust. If choosing between dense analytics and emotional clarity, choose emotional clarity. If choosing between generic AI design and a private journal feel, choose the private journal feel.
