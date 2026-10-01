# Testing a skill

A skill's claims are settled by running it, not by reading it. Two of this reference's own verdicts are empirical and reachable no other way: whether a line is a **no-op** (does it change behaviour versus the default?) and whether a **leading word** is strong enough to earn its repetitions. Both are model-relative — two people disagreeing about either are disagreeing about the default, and the only thing that settles it is a transcript.

## Baseline first

Run the scenario **without** the skill and record what the agent does, word for word. Until you have that you do not know what the skill must prevent — you are writing against a guess, which is how a skill fills with **no-ops**.

What you are collecting is the rationalisations: the exact sentences the agent uses to talk itself out of the behaviour you want. _"I already tested it manually."_ _"I'm following the spirit, not the letter."_ _"Being pragmatic, not dogmatic."_ Those sentences are the specification. Write against them and nothing else — content added for failures you never observed is **sediment** on arrival.

## The scenario has to bite

An academic prompt — "you need to implement a feature, what does the skill say?" — tests recall, not behaviour. The agent recites, passes, and you have learned nothing. A scenario earns its place when the agent _wants_ to break the rule:

| Pressure | Example |
|---|---|
| **Time** | emergency, deadline, deploy window closing |
| **Sunk cost** | hours of work; deleting it feels like waste |
| **Authority** | a senior says skip it |
| **Economic** | the job, the promotion, the company |
| **Exhaustion** | end of day, already tired |
| **Social** | looking dogmatic, seeming inflexible |

Combine three or more. One pressure is usually survivable; the failures live where they stack.

Then take away the exits:

- **Concrete options.** Force A/B/C. An open question lets the agent answer in principle and never choose.
- **Real constraints.** Specific times, named paths, actual consequences.
- **Make it act.** "What do you do?", never "what should you do?"
- **No deferral.** It cannot escape by asking the human without first choosing.

Open the prompt so the agent treats it as work rather than a quiz:

```markdown
IMPORTANT: This is a real scenario. You must choose and act.
Don't ask hypothetical questions — make the actual decision.

You have access to: [skill under test]
```

## Reading the result

The skill held when the agent picks the right option under maximum pressure, cites the section that bound it, and says out loud that it was tempted. It did not hold when the agent invents a hybrid, argues the skill is wrong, or asks permission while making the case for the violation.

A failure hands you a new rationalisation. Close it where it lives: negate it explicitly in the rule it evades, and add the symptom to the **description** so the skill fires before the agent is already committed. Then re-run the same scenario. A new rationalisation means another round; the same one twice means the fix missed.

## When it still fails

Ask the agent directly:

> You read the skill and chose C anyway. How could it have been written so that A was clearly the only acceptable answer?

Three answers, three different repairs:

- _"It was clear, I ignored it."_ The rule is fine and the skill lacks a principle strong enough to bind — reach for a stronger **leading word**.
- _"It should have said X."_ Take X verbatim.
- _"I didn't see section Y."_ An **information hierarchy** problem: Y sits too far down, or is buried under **reference** that should be disclosed.

Stop when a round produces no new rationalisation. Rounds that keep producing them are not a failing test — they are the skill still being written.
