package bridge

import (
	"encoding/json"
	"github.com/mknoon/go-mknoon/node"
)

// Diagnostic serialization must never replace the ordinary command result.
func withConnectionDiagnostics(response string, observations []node.ConnectionDiagnostic) (result string) {
	result = response
	defer func() { _ = recover() }()
	if len(observations) == 0 {
		return
	}
	var value map[string]interface{}
	if json.Unmarshal([]byte(response), &value) != nil {
		return
	}
	value["connectionDiagnostics"] = observations
	if encoded, err := json.Marshal(value); err == nil {
		result = string(encoded)
	}
	return
}
