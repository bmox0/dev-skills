# Moments

What a moment is, how its storyboard is written, and when you offer to draw it.
Reached from [`SKILL.md`](../SKILL.md) when the work puts something new in front
of a person.

## A moment is not a story

A story is what the work is for. A moment is what a person is put in front of,
and in what order. One moment usually gathers several stories, so the two counts
differ and that is the normal case: on the `provider-settings-migration` plan
eight user stories were three moments, and the migration modal alone gathered
US-1, US-2 and US-3 into one sequence.

Write one moment per thing a person meets, not one per story.

## The storyboard is in the person's words

The mechanism does not appear in a storyboard. This is what the section exists
for, and it has already failed once in a way worth reproducing.

On `provider-settings-migration` the human was asked:

> Migration direction: when both sides hold a value and `updatedAt` ties, which
> `SyncStrategy` wins? (recommended: remote)

A well-formed question. They picked the recommended answer, and eleven phases
later opened the built modal and said *"what even is direction choice — I didn't
understand we have a conflict and are resolving it."*

The same decision, written as a moment:

```markdown
- **M-2. Finding out your two devices disagree** · US-1, US-2, US-3
  1. You turn on sync on your laptop, having already used the app on your phone.
  2. A panel says both devices have settings and they do not match, and shows
     you the two side by side.
  3. You pick the one to keep. Nothing is overwritten until you do.
  4. The other device catches up next time it syncs, and the panel is gone.
```

Same code, same decision — and a human reads step 2 and either recognises their
situation or says *"wait, when does that happen?"*, which is the sentence the
plan needed eleven phases earlier.

The shape is a heading naming what the person is doing and the stories it
gathers, then at least two steps, numbered and indented two. `plan-check` rejects
a malformed one by name, so a broken moment surfaces while the plan is still in
front of you.

**Check every step against the person:** could they have said it themselves,
never having seen the code? A step carrying `SyncStrategy`, `updatedAt`, a
component name or a table name failed that check — rewrite the step, do not
annotate it.

## Offer to draw the moment

### When

After the last question about that moment is answered, and before phases are laid
out. Both halves carry weight. Earlier, the moment is not whole yet and you draw
a sequence you are still asking about. Later, "no, that's not it" reopens a
topology; here it reopens one cluster of questions, which is a conversation
rather than a rewrite.

### The offer

One message, and it leans:

> I'll draw this moment — say if you don't want it.

Silence means yes. One word means no, and no ends it for that moment: you do not
raise it again, and the interview keeps its shape.

**No hedge, and no neutral question.** `dev-skills:grill`'s visual companion
carries this same offer with "it can be token-intensive" attached, and across 31
measured sessions it was never once offered. A question with no lean collects
"later" in the middle of an interview, and later never comes. The default is that
the moment gets drawn.

### Dispatching the prototyper

Dispatch **`dev-skills:prototyper`** with three things and nothing else:

- the moment's storyboard, verbatim;
- the plan title;
- the absolute output path `.ai-workflow/plans/<plan>/prototypes/M-<n>.html`.

The seat reads its own definition; a dispatch that repeats it pays for the same
instructions twice.

It returns the path it wrote, and one line per step it could not draw without
inventing something. **Each of those lines is a question you have not asked yet**
— put it to the human before the next moment.

The file is already in their browser by the time the seat returns — a hook
opens every prototype the moment it is written — so give the human the path and
nothing else; do not tell them to open it. No server starts and there is nothing
to shut down afterwards: the file stands on its own and opens from disk.

What comes back — the wrong order, a step that does not belong, a step nobody
wrote down — is a change to the storyboard, and the storyboard is what the plan
carries. Make it there, then go on to the next moment.
