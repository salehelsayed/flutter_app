package bridge

import (
	"go/ast"
	"go/parser"
	"go/token"
	"os"
	"strings"
	"testing"
)

func TestBridgeExportedHandlersUseSharedEntrypoint(t *testing.T) {
	for _, name := range []string{"StartNode", "GroupPublish", "GroupSendReliable"} {
		if !functionCallsHelper(t, "bridge.go", name, "withBridgeNode") {
			t.Fatalf("%s should delegate singleton lookup/panic wrapping through withBridgeNode", name)
		}
	}
}

func TestBridgeGroupPublishContractsPreservedAfterHelperExtraction(t *testing.T) {
	t.Run("not initialized", func(t *testing.T) {
		withNoSingletonNode(t)
		for _, tc := range []struct {
			name string
			call func(string) string
		}{
			{name: "GroupPublish", call: GroupPublish},
			{name: "GroupSendReliable", call: GroupSendReliable},
		} {
			m := parseJSON(t, tc.call(`{}`))
			assertNotOk(t, m, "NOT_INITIALIZED")
			if !strings.Contains(m["errorMessage"].(string), "call Initialize first") {
				t.Fatalf("%s not-initialized message = %v", tc.name, m["errorMessage"])
			}
		}
	})

	t.Run("invalid input and node errors", func(t *testing.T) {
		withFreshSingletonNode(t)
		for _, tc := range []struct {
			name string
			call func(string) string
		}{
			{name: "GroupPublish", call: GroupPublish},
			{name: "GroupSendReliable", call: GroupSendReliable},
		} {
			invalid := parseJSON(t, tc.call(`not json`))
			assertNotOk(t, invalid, "INVALID_INPUT")
			if !strings.Contains(invalid["errorMessage"].(string), "invalid JSON") {
				t.Fatalf("%s invalid input message = %v", tc.name, invalid["errorMessage"])
			}

			missing := parseJSON(t, tc.call(`{}`))
			assertNotOk(t, missing, "INVALID_INPUT")

			notStarted := parseJSON(t, tc.call(validGroupSendParamsJSON()))
			assertNotOk(t, notStarted, "GROUP_ERROR")
			if strings.TrimSpace(notStarted["errorMessage"].(string)) == "" {
				t.Fatalf("%s node error message was empty", tc.name)
			}
		}
	})
}

func withNoSingletonNode(t *testing.T) {
	t.Helper()
	nodeMu.Lock()
	prevNode := singletonNode
	prevAdapter := singletonCallbackAdapter
	singletonNode = nil
	singletonCallbackAdapter = nil
	nodeMu.Unlock()

	t.Cleanup(func() {
		nodeMu.Lock()
		singletonNode = prevNode
		singletonCallbackAdapter = prevAdapter
		nodeMu.Unlock()
	})
}

func validGroupSendParamsJSON() string {
	return `{
		"groupId": "bridge-entrypoint-contract",
		"text": "hello",
		"senderPeerId": "sender-peer",
		"senderPublicKey": "sender-public-key",
		"senderPrivateKey": "sender-private-key",
		"senderUsername": "sender"
	}`
}

func functionCallsHelper(t *testing.T, path string, funcName string, helperName string) bool {
	t.Helper()
	src, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read %s: %v", path, err)
	}
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, path, src, parser.ParseComments)
	if err != nil {
		t.Fatalf("parse %s: %v", path, err)
	}
	var target *ast.FuncDecl
	for _, decl := range file.Decls {
		fn, ok := decl.(*ast.FuncDecl)
		if ok && fn.Name.Name == funcName {
			target = fn
			break
		}
	}
	if target == nil {
		t.Fatalf("function %s not found", funcName)
	}
	found := false
	ast.Inspect(target.Body, func(n ast.Node) bool {
		call, ok := n.(*ast.CallExpr)
		if !ok {
			return true
		}
		if ident, ok := call.Fun.(*ast.Ident); ok && ident.Name == helperName {
			found = true
			return false
		}
		return true
	})
	return found
}
