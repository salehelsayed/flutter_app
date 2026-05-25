# G3-REACT-001 Session Plan And Closure

Source rows: G3-011, G3-012, G3-013, G3-014.

## Scope

- Scope outbound reaction targets to the requested group.
- Enforce outbound sender signing key authorization against legacy member key or active device key.
- Validate incoming/replayed target message group when message repository state is available.
- Reject invalid reaction actions, invalid timestamps, and blank required fields during payload parse.
- Use deterministic IDs for add reaction sends.

## Closure Evidence

- Implemented in reaction send/receive use cases and reaction payload model.
- Replay call sites pass message repository context where available.
- Focused reaction tests cover cross-group target rejection, unauthorized sender key rejection, invalid action rejection, and deterministic add IDs.
- Verification: included in the controller focused gate, `+169: All tests passed!`.

## Residual Out Of Scope

Durable pending reaction state for unknown target messages remains G3-015 and was intentionally skipped.

## Verdict

Accepted and closed.
