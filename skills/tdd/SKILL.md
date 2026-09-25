---
name: tdd
description: "Red before green: one failing test at the seam the brief names, then the simplest code that passes. Read by the builder when a step has tests."
user-invocable: false
---

# Red before green

The brief's step names the seam: the place where the behaviour is observable,
and the test that goes red first. Write tests there, the way the neighbouring
tests in the project are written.

## The cycle

1. **Red.** One test, one behaviour, a name that says what should happen. Run
   it and watch it fail: it fails rather than errors, with the message you
   expected, because the behaviour is missing. A test that passes at once is
   testing something that already exists; a test you did not watch fail may not
   test anything.
2. **Green.** The simplest code that passes. Nothing the step does not need.
3. **Green everywhere.** The test passes, its neighbours still pass, the output
   is clean. Tidy names and duplication only while green.

Production code written before its test is deleted and written again from the
test.

## Keeping a test honest

- **Derive the expectation by hand.** A value computed by the code under test
  passes whatever that code does.
- **Assert on behaviour, not on a mock.** Mock the slow or external edge, keep
  what the test depends on real, and mirror the real shape completely.
- **Name the break it catches.** If the only change that fails it is a
  deliberate one (a constant, exact wording, private structure), it will fire on
  every redesign and sleep through every bug.
- **A test that can fail only through a crash or a missing selector is not a
  test.** Review counts it as a Defect.
