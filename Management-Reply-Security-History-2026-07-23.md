Subject: Re: Visitor Parking App — Security & History Questions

Hi all,

Quick answers to your questions below.

**What protects the license plate, phone #, and unit #?**
We've actually removed phone number collection entirely — residents are no longer asked for it, and any numbers previously stored are being purged, so there's nothing left to protect on that front. Plate and unit number are encrypted in transit (HTTPS) and stored in a database with role-based access control, so they're only ever visible to logged-in staff, never the public. Unit codes (the "password" residents use) are never exposed to the browser at all — the system checks it server-side and only ever returns a yes/no match.

**Unit's remaining monthly permits** — already live. Shown right on the registration confirmation screen (e.g., "7 of 10 passes used this month").

**History of a plate's permit use** — now available. Admin has a new Registration History tab where staff can look up any plate and see every time it's been registered, active or expired.

**History of a unit's permit use** — same tool, same tab: staff can search by unit number instead to see that unit's full registration history.

One addition worth flagging: history is kept for 3 years, then automatically and permanently deleted — so we're retaining what's useful without holding onto it indefinitely.

Happy to do a live walkthrough if helpful.

Best,
Sameer
