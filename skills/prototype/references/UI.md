# UI Prototype

Several radically different UI variants on one route, switched from a
floating bottom bar, gated by a `?variant=` URL param on the page the user
named. Its real data and fetching stay; only the rendered subtree swaps.

## Where the variants go

On the page the user named, or, when the surface is new, a throwaway route
following the project's own routing convention, named so it's obviously a
prototype (e.g. `prototype` in the path). Either way, the same `?variant=`
param and the same floating bar.

## Process

1. **State the question**, one line: "Three variants of the settings page,
   switchable via `?variant=`, on `/settings`."
2. **Generate the variants** the user named, at most 5. Each must fit the
   page's purpose and data, use the project's own component library, and
   export a clear name (`VariantA`, `VariantB`...). They must be
   **structurally different** — layout, information hierarchy, primary
   affordance — not just colour or copy; two that look alike get redone.
3. **Wire them behind a switcher**, above which the existing data fetching
   stays untouched:

   ```tsx
   const variant = searchParams.get('variant') ?? 'A';
   return (
     <>
       {variant === 'A' && <VariantA {...data} />}
       {variant === 'B' && <VariantB {...data} />}
       <PrototypeSwitcher variants={['A', 'B']} current={variant} />
     </>
   );
   ```

4. **Build the floating switcher**, one shared component: a left and a right
   arrow that cycle (wrapping) and update the URL via the framework's router,
   a label showing the current variant's key and name, and `←`/`→` doing the
   same unless an input is focused. Visually distinct from the page, and
   gated on `process.env.NODE_ENV !== 'production'` so it can't ship.
5. **Open it** yourself — `open <url>` on macOS, `xdg-open` elsewhere —
   starting the dev server first if needed, then surface the `?variant=`
   keys.
6. **Capture the answer** the way [SKILL](../SKILL.md) describes, with a
   screenshot of each variant under `.ai-workflow/prototypes/` first. Then
   remove every variant, the switcher and any throwaway route — the plan's
   build writes the winner properly.

## Anti-patterns

- Variants differing only in colour or copy — that's a tweak, not a
  prototype.
- A shared `<Layout>` between variants — a shared `<Header>` is fine, a
  shared layout defeats the point.
- Wiring a variant to a real mutation — point it at a stub instead.
- Promoting prototype code straight to production — rewrite it under real
  constraints.
