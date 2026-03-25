package bridge

import (
	"encoding/json"
	"testing"
)

func TestGroupGenerateNextKey_NodeNotInitialized(t *testing.T) {
	withNilSingleton(t)

	result := GroupGenerateNextKey(`{"groupId":"g1"}`)
	assertNotOk(t, parseJSON(t, result), "NOT_INITIALIZED")
}

func TestGroupGenerateNextKey_InvalidJSON(t *testing.T) {
	withFreshSingletonNode(t)

	result := GroupGenerateNextKey("not valid json")
	assertNotOk(t, parseJSON(t, result), "INVALID_INPUT")
}

func TestGroupGenerateNextKey_MissingGroupId(t *testing.T) {
	withFreshSingletonNode(t)

	result := GroupGenerateNextKey(`{}`)
	assertNotOk(t, parseJSON(t, result), "INVALID_INPUT")
}

func TestGroupGenerateNextKey_DoesNotMutateStoredKeyState(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	startResult := StartNode(startNodeJSON(t, keyHex))
	assertOk(t, parseJSON(t, startResult))

	genIdentity := parseJSON(t, GenerateIdentity())
	assertOk(t, genIdentity)
	identity := genIdentity["identity"].(map[string]interface{})

	createInput, _ := json.Marshal(map[string]interface{}{
		"name":             "Generate Next Key Group",
		"groupType":        "chat",
		"creatorPeerId":    identity["peerId"].(string),
		"creatorPublicKey": identity["publicKey"].(string),
	})
	createMap := parseJSON(t, GroupCreate(string(createInput)))
	assertOk(t, createMap)

	groupId := createMap["groupId"].(string)

	nodeMu.Lock()
	initialKeyInfo := singletonNode.GetGroupKeyInfo(groupId)
	nodeMu.Unlock()
	if initialKeyInfo == nil {
		t.Fatal("expected stored key info after group create")
	}
	initialKey := initialKeyInfo.Key
	initialEpoch := initialKeyInfo.KeyEpoch

	nextInput, _ := json.Marshal(map[string]string{"groupId": groupId})
	nextMap := parseJSON(t, GroupGenerateNextKey(string(nextInput)))
	assertOk(t, nextMap)

	nextEpoch, ok := nextMap["keyEpoch"].(float64)
	if !ok {
		t.Fatal("response missing keyEpoch")
	}
	if int(nextEpoch) != initialEpoch+1 {
		t.Fatalf("expected next keyEpoch=%d, got %d", initialEpoch+1, int(nextEpoch))
	}
	nextKey, ok := nextMap["groupKey"].(string)
	if !ok || nextKey == "" {
		t.Fatal("response missing non-empty groupKey")
	}

	nodeMu.Lock()
	storedAfter := singletonNode.GetGroupKeyInfo(groupId)
	nodeMu.Unlock()
	if storedAfter == nil {
		t.Fatal("expected stored key info after generateNextKey")
	}
	if storedAfter.Key != initialKey {
		t.Fatalf("generateNextKey should not mutate current key: got %q want %q", storedAfter.Key, initialKey)
	}
	if storedAfter.KeyEpoch != initialEpoch {
		t.Fatalf("generateNextKey should not mutate current epoch: got %d want %d", storedAfter.KeyEpoch, initialEpoch)
	}
}
