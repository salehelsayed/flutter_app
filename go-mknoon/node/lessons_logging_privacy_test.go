package node

import (
	"strings"
	"testing"
)

func TestLL55NodeStartupDoesNotExposeAnnouncedAddressInConsole(t *testing.T) {
	avInstallAnetShaped(t, avMarkerPrivateIP)
	logs := captureLP002ValidatorLogs(t)
	n := avStartLocalNode(t)

	if !avSliceContains(n.State().Addresses, avMarkerPrivateIP) {
		t.Fatal("fixture did not exercise a real startup announcement containing the synthetic address")
	}
	// The address remains usable by the transport, but is not console data.
	// Capture the standard Go logger used by Node.Start, not Dart's sanitizer.
	if strings.Contains(logs.String(), avMarkerPrivateIP) {
		t.Fatal("real node startup leaked its announced address through the standard Go log sink")
	}
}
