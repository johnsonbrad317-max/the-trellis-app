# The Trellis: web preview test plan (for an AI tester)

You are testing **The Trellis**, an iPhone app for Christian discipleship and accountability, through its **web preview** at:

**[WEB PREVIEW LINK]**

The web preview is the real app running in a browser. It uses the **live database** (the same one beta testers use on their phones), so everything you create is real. Only use the five test identities below, and only pair them with each other.

Read `docs/PROJECT_BRIEF.md` if you have it. In short:

- A **Runner** writes a *Rule of Life* (rhythms to keep, sins to "throw off") and checks in each morning on the day before.
- A **Witness** walks with Runners: sees their Rule, check-ins and shared prayers, prays, and suggests meetings.
- A **Cloud** is a church leader with an aggregate view.

---

## Phone-only (not bugs on the web)

The green strip at the top of every page says so. These don't work in a browser:

- Push notifications and daily reminders
- Calendar sharing
- "Text" buttons, which open Messages; on a computer they may do nothing
- Café and lunch suggestions in Connect (turned off in this build)

Report anything else that fails, looks broken or reads oddly.

---

## The five test identities

Each tester signs up through **New here? Begin the journey** on the Sign In page. The owner gives you each password separately. Never use a made-up email address: these plus-addresses all deliver to the owner's inbox.

| # | Name | Email | Mobile | Plays |
|---|------|-------|--------|-------|
| 1 | Grace Tester | johnsonbrad317+grok1@gmail.com | 555-0101 | Runner using a **starter Rule** |
| 2 | Paul Tester | johnsonbrad317+grok2@gmail.com | 555-0102 | Runner who **builds his own Rule** |
| 3 | Lydia Tester | johnsonbrad317+grok3@gmail.com | 555-0103 | **Witness** for Grace and Paul |
| 4 | Silas Tester | johnsonbrad317+grok4@gmail.com | 555-0104 | Second **Witness** for Grace |
| 5 | Ruth Tester | johnsonbrad317+grok5@gmail.com | 555-0105 | **Cloud** preview, then Runner edge cases |

Leave the church code empty. The 555-01xx numbers are reserved for fiction, so nobody real is ever texted.

If sign-up says "Check your email for a confirmation link," stop and tell the owner. He will confirm the address, then you sign in.

---

## Scenarios

Work through these in order and note anything confusing, broken, slow, misaligned, or worded strangely.

### A. First run (each identity)
1. Sign up. Read the whole welcome deck. Use **Next**, and also try swiping.
2. On the last slide, choose the role from the table.
3. Check the dashboard's **Getting Started** list makes sense.

### B. Grace: starter Rule
1. Choose a starter Rule (for example "Working Parent") and commit it.
2. Open **Rule of Life**:
   - Rename a rhythm.
   - Change a weekly rhythm's days.
   - Add a sin to throw off.
   - Try adding a rhythm typed as "No social media after 9". It should land under *Sins to Throw Off* as "Avoid social media after 9".
3. Make one rhythm an **Anchor Rhythm**.
4. Open **Today's Check-In**, answer every question, and submit.
5. Open it again. It should show your answers as *locked in*, with no Submit button.

### C. Grace: invite Witnesses
1. Tap the person-with-a-plus icon (**Generate Witness Code**) and note the code.
2. As **Lydia** (Witness), enter the code ("Enter a pairing code"). Lydia should now see Grace.
3. Generate another code as Grace, and pair **Silas** the same way.
4. As **Paul**, build a Rule, generate a code, and pair **Lydia** too. Lydia now walks with two Runners.

### D. Prayer
1. As Grace, add a person and a situation in the **Prayer** tab.
   - On one, use **Choose a verse** under Scripture: pick a theme and try **Different verse**.
   - On the other, type a reference by hand.
2. Edit a prayer: in **Edit/Manage** (pencil icon) use the pencil, or open it and tap **Edit**.
3. Share one prayer with **only Silas**: turn on "Share with Witness(es)" and deselect Lydia.
4. Check that Silas sees it and Lydia doesn't.
5. Run **Begin Daily Prayer**: swipe through the cards, then open the "Text …" step and look at the **Add a verse?** sheet. The text itself won't send on a computer.

### E. Witness views (Lydia and Silas)
1. Switch between Grace and Paul.
2. Read their Rule of Life, the week's progress, and the shared prayers.
3. Pray through a Runner's shared prayers.
4. On **Connect**, suggest a meeting (coffee or lunch). As the Runner, accept or answer it.
5. **Pull down** on a tab to refresh. New data should appear without reloading the page.

### F. Ruth: Cloud and edge cases
1. Switch to **Cloud**. When asked for a code, choose **See Preview** and look around the sample church. Then exit the preview.
2. Switch back to Runner and build a Rule, but **don't commit it**. Check nothing counts against her yet.
3. Try **Forgot your password?** on the Sign In page once, then stop at the code step: the email goes to the owner.

### G. Everywhere
- Try the page at **phone width** (about 390px) and at **desktop width**.
- Look for overlapping text, cut-off buttons, or anything you can't reach.
- Try the menu (top-left): Account & Membership, Notification Settings, the welcome deck again, Send Feedback.

---

## Reporting

For each problem, give:

1. Which identity, and where (tab or screen)
2. What you did, step by step
3. What you expected, and what happened, quoting any message word for word
4. The page width

Please also note anything that worked but felt confusing or poorly worded. That's as useful as a crash.

**Don't:**
- Pair with any account outside the five above
- Use a church code
- Type a real person's details
- Click "Delete Account" (the owner removes the test accounts afterward)
