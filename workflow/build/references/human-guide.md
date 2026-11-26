# Guide to the landed build

After judge and land, recover the original conversation language from the handoff per [SESSIONS.md](../../../references/SESSIONS.md).
Use it in the guide. Follow the [filled example](example.guide.md). Give the exact
URL, artifact or worktree path, how to open it, and how to respond. Include limits
on checks and whether later changes touched any flagged result.

Use two level-four Markdown headings in the same language as the guide.

1. Under the first heading, write each check on its own line as
   `- **Done N** action → visible result`. On a small gate include every plan
   Done item. On a normal gate include each marked `you check`. Refer to any
   other current Done case by its number or add a `Check N` for behavior
   decided during the build. Each reference is unique.
2. Under the second heading, write one bullet per outstanding human decision.
   Give the relevant finding ID, the effect on the human and the available
   choices. Include what would be deferred if the result is accepted.

Use a lone `- —` in an empty list. Save the guide as a UTF-8 file such as
`<slug>.guide.md` beside the plan, or pass the Markdown inline. `CLI page`
prints the complete message for the contact. `CLI page <plan> --show` reads it
again for handoff while that page is current. Relay it verbatim. Result acceptance
is separate from plan approval.

For a new land after a round, write the guide from the new result and obtain
acceptance of the current page. If the plan was already passed, return to
building before replacing the page. Acceptance binds the page's guide and
ending along with the judge, land and records.
