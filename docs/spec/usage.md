# Usage reports

Session measurements through explicit transcript-format adapters.

### format-is-explicit — Format readers and native log roots belong to explicit optional adapters, without a common fixed catalogue or implicit host default

Why: transcript schemas identify hosts rather than inference providers

- Run existing transcript fixtures through explicit sources → filters, message exports, errors, token/cache accounting and descendants match baseline; omitted/unknown source refuses without guessing or reading another format.

### measurements-preserved — Existing readers preserve filters, exports, token accounting, descendants and errors

Why: removing dispatch coupling must not lose or miscount data

- Run existing transcript fixtures through explicit sources → filters, message exports, errors, token/cache accounting and descendants match baseline; omitted/unknown source refuses without guessing or reading another format.
