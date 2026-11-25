package node

import (
	"context"
	"errors"
	"fmt"
)

var (
	ErrNodeNotStarted   = errors.New("node not started")
	ErrRelayUnavailable = errors.New("relay unavailable")
)

type nodeErrorWithKind struct {
	error
	kind error
}

func (e nodeErrorWithKind) Is(target error) bool { return target == e.kind }
func (e nodeErrorWithKind) Unwrap() error        { return e.error }

func relayAcquisitionError(ctx context.Context, operation string, cause error) error {
	err := fmt.Errorf("%s: %w", operation, cause)
	if ctx.Err() == context.Canceled || errors.Is(cause, context.Canceled) {
		return err
	}
	return nodeErrorWithKind{error: err, kind: ErrRelayUnavailable}
}
