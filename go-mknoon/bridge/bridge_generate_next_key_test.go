package bridge

import (
	"encoding/json"
	"testing"
	"time"
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
		"name":                  "Generate Next Key Group",
		"groupType":             "chat",
		"creatorPeerId":         identity["peerId"].(string),
		"creatorPublicKey":      identity["publicKey"].(string),
		"creatorMlKemPublicKey": "mlkem-pk-creator",
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

func TestGroupGenerateNextKey_KE002UsesLatestCommittedEpochWithoutMutating(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	startResult := StartNode(startNodeJSON(t, keyHex))
	assertOk(t, parseJSON(t, startResult))

	genIdentity := parseJSON(t, GenerateIdentity())
	assertOk(t, genIdentity)
	identity := genIdentity["identity"].(map[string]interface{})

	createInput, _ := json.Marshal(map[string]interface{}{
		"name":                  "KE-002 Generate Next Key Group",
		"groupType":             "chat",
		"creatorPeerId":         identity["peerId"].(string),
		"creatorPublicKey":      identity["publicKey"].(string),
		"creatorMlKemPublicKey": "mlkem-pk-creator",
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
	firstNextMap := parseJSON(t, GroupGenerateNextKey(string(nextInput)))
	assertOk(t, firstNextMap)

	firstNextEpoch, ok := firstNextMap["keyEpoch"].(float64)
	if !ok {
		t.Fatal("first response missing keyEpoch")
	}
	if int(firstNextEpoch) != initialEpoch+1 {
		t.Fatalf("expected first next keyEpoch=%d, got %d", initialEpoch+1, int(firstNextEpoch))
	}
	firstNextKey, ok := firstNextMap["groupKey"].(string)
	if !ok || firstNextKey == "" {
		t.Fatal("first response missing non-empty groupKey")
	}

	nodeMu.Lock()
	storedAfterFirstGenerate := singletonNode.GetGroupKeyInfo(groupId)
	nodeMu.Unlock()
	if storedAfterFirstGenerate == nil {
		t.Fatal("expected stored key info after first generateNextKey")
	}
	if storedAfterFirstGenerate.Key != initialKey {
		t.Fatalf("first generateNextKey should not mutate current key: got %q want %q", storedAfterFirstGenerate.Key, initialKey)
	}
	if storedAfterFirstGenerate.KeyEpoch != initialEpoch {
		t.Fatalf("first generateNextKey should not mutate current epoch: got %d want %d", storedAfterFirstGenerate.KeyEpoch, initialEpoch)
	}

	updateInput, _ := json.Marshal(map[string]interface{}{
		"groupId":  groupId,
		"groupKey": firstNextKey,
		"keyEpoch": int(firstNextEpoch),
	})
	updateMap := parseJSON(t, GroupUpdateKey(string(updateInput)))
	assertOk(t, updateMap)

	nodeMu.Lock()
	storedAfterUpdate := singletonNode.GetGroupKeyInfo(groupId)
	nodeMu.Unlock()
	if storedAfterUpdate == nil {
		t.Fatal("expected stored key info after updateKey")
	}
	if storedAfterUpdate.Key != firstNextKey {
		t.Fatalf("updateKey should commit generated key: got %q want %q", storedAfterUpdate.Key, firstNextKey)
	}
	if storedAfterUpdate.KeyEpoch != int(firstNextEpoch) {
		t.Fatalf("updateKey should commit generated epoch: got %d want %d", storedAfterUpdate.KeyEpoch, int(firstNextEpoch))
	}
	committedKey := storedAfterUpdate.Key
	committedEpoch := storedAfterUpdate.KeyEpoch
	committedPrevKey := storedAfterUpdate.PrevKey
	committedPrevEpoch := storedAfterUpdate.PrevKeyEpoch
	committedGraceDeadline := storedAfterUpdate.GraceDeadline
	if committedPrevKey == "" || committedGraceDeadline.IsZero() || !time.Now().Before(committedGraceDeadline) {
		t.Fatalf("expected committed rotation to leave active previous-key grace, got prevKey=%q deadline=%v", committedPrevKey, committedGraceDeadline)
	}

	secondNextMap := parseJSON(t, GroupGenerateNextKey(string(nextInput)))
	assertNotOk(t, secondNextMap, "GROUP_KEY_GRACE_ACTIVE")
	if _, ok := secondNextMap["groupKey"]; ok {
		t.Fatal("active grace rejection must not include groupKey")
	}
	if _, ok := secondNextMap["keyEpoch"]; ok {
		t.Fatal("active grace rejection must not include keyEpoch")
	}

	nodeMu.Lock()
	storedAfterSecondGenerate := singletonNode.GetGroupKeyInfo(groupId)
	nodeMu.Unlock()
	if storedAfterSecondGenerate == nil {
		t.Fatal("expected stored key info after second generateNextKey")
	}
	if storedAfterSecondGenerate.Key != committedKey {
		t.Fatalf("second generateNextKey should not mutate current key: got %q want %q", storedAfterSecondGenerate.Key, committedKey)
	}
	if storedAfterSecondGenerate.KeyEpoch != committedEpoch {
		t.Fatalf("second generateNextKey should not mutate current epoch: got %d want %d", storedAfterSecondGenerate.KeyEpoch, committedEpoch)
	}
	if storedAfterSecondGenerate.PrevKey != committedPrevKey || storedAfterSecondGenerate.PrevKeyEpoch != committedPrevEpoch {
		t.Fatalf("second generateNextKey should not mutate previous key state: got epoch=%d key=%q want epoch=%d key=%q", storedAfterSecondGenerate.PrevKeyEpoch, storedAfterSecondGenerate.PrevKey, committedPrevEpoch, committedPrevKey)
	}
	if !storedAfterSecondGenerate.GraceDeadline.Equal(committedGraceDeadline) {
		t.Fatalf("second generateNextKey should not mutate grace deadline: got %v want %v", storedAfterSecondGenerate.GraceDeadline, committedGraceDeadline)
	}
}

func TestGroupGenerateNextKey_GroupKeyGraceActiveRejectsSecondNativeRotation(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	startResult := StartNode(startNodeJSON(t, keyHex))
	assertOk(t, parseJSON(t, startResult))

	genIdentity := parseJSON(t, GenerateIdentity())
	assertOk(t, genIdentity)
	identity := genIdentity["identity"].(map[string]interface{})

	createInput, _ := json.Marshal(map[string]interface{}{
		"name":                  "GKGC Active Grace Generate Next Key Group",
		"groupType":             "chat",
		"creatorPeerId":         identity["peerId"].(string),
		"creatorPublicKey":      identity["publicKey"].(string),
		"creatorMlKemPublicKey": "mlkem-pk-creator",
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
	firstNextMap := parseJSON(t, GroupGenerateNextKey(string(nextInput)))
	assertOk(t, firstNextMap)
	firstNextKey, ok := firstNextMap["groupKey"].(string)
	if !ok || firstNextKey == "" {
		t.Fatal("first response missing non-empty groupKey")
	}
	firstNextEpoch, ok := firstNextMap["keyEpoch"].(float64)
	if !ok || int(firstNextEpoch) != initialEpoch+1 {
		t.Fatalf("first keyEpoch = %v, want %d", firstNextMap["keyEpoch"], initialEpoch+1)
	}

	updateInput, _ := json.Marshal(map[string]interface{}{
		"groupId":  groupId,
		"groupKey": firstNextKey,
		"keyEpoch": int(firstNextEpoch),
	})
	updateMap := parseJSON(t, GroupUpdateKey(string(updateInput)))
	assertOk(t, updateMap)

	nodeMu.Lock()
	storedBeforeReject := singletonNode.GetGroupKeyInfo(groupId)
	nodeMu.Unlock()
	if storedBeforeReject == nil {
		t.Fatal("expected stored key info after updateKey")
	}
	if storedBeforeReject.Key != firstNextKey || storedBeforeReject.KeyEpoch != int(firstNextEpoch) {
		t.Fatalf("committed key state = epoch %d key %q, want epoch %d key %q", storedBeforeReject.KeyEpoch, storedBeforeReject.Key, int(firstNextEpoch), firstNextKey)
	}
	if storedBeforeReject.PrevKey != initialKey || storedBeforeReject.PrevKeyEpoch != initialEpoch {
		t.Fatalf("previous key state = epoch %d key %q, want epoch %d key %q", storedBeforeReject.PrevKeyEpoch, storedBeforeReject.PrevKey, initialEpoch, initialKey)
	}
	if storedBeforeReject.GraceDeadline.IsZero() || !time.Now().Before(storedBeforeReject.GraceDeadline) {
		t.Fatalf("expected active previous-key grace before second generate, got deadline %v", storedBeforeReject.GraceDeadline)
	}

	secondNextMap := parseJSON(t, GroupGenerateNextKey(string(nextInput)))
	assertNotOk(t, secondNextMap, "GROUP_KEY_GRACE_ACTIVE")
	if _, ok := secondNextMap["groupKey"]; ok {
		t.Fatal("active grace rejection must not include groupKey")
	}
	if _, ok := secondNextMap["keyEpoch"]; ok {
		t.Fatal("active grace rejection must not include keyEpoch")
	}

	nodeMu.Lock()
	storedAfterReject := singletonNode.GetGroupKeyInfo(groupId)
	nodeMu.Unlock()
	if storedAfterReject == nil {
		t.Fatal("expected stored key info after rejected generateNextKey")
	}
	if storedAfterReject.Key != storedBeforeReject.Key || storedAfterReject.KeyEpoch != storedBeforeReject.KeyEpoch {
		t.Fatalf("rejected generateNextKey mutated current key state: got epoch %d key %q want epoch %d key %q", storedAfterReject.KeyEpoch, storedAfterReject.Key, storedBeforeReject.KeyEpoch, storedBeforeReject.Key)
	}
	if storedAfterReject.PrevKey != storedBeforeReject.PrevKey || storedAfterReject.PrevKeyEpoch != storedBeforeReject.PrevKeyEpoch {
		t.Fatalf("rejected generateNextKey mutated previous key state: got epoch %d key %q want epoch %d key %q", storedAfterReject.PrevKeyEpoch, storedAfterReject.PrevKey, storedBeforeReject.PrevKeyEpoch, storedBeforeReject.PrevKey)
	}
	if !storedAfterReject.GraceDeadline.Equal(storedBeforeReject.GraceDeadline) {
		t.Fatalf("rejected generateNextKey mutated grace deadline: got %v want %v", storedAfterReject.GraceDeadline, storedBeforeReject.GraceDeadline)
	}
}

func TestGroupGenerateNextKey_KE013BlocksWhenGroupKeyStateMissing(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	startResult := StartNode(startNodeJSON(t, keyHex))
	assertOk(t, parseJSON(t, startResult))

	result := GroupGenerateNextKey(`{"groupId":"ke013-missing-group"}`)
	resultMap := parseJSON(t, result)
	assertNotOk(t, resultMap, "GROUP_KEY_NOT_FOUND")
	if _, ok := resultMap["keyEpoch"]; ok {
		t.Fatal("missing key state response must not include keyEpoch")
	}
}

func TestGroupGenerateNextKey_KE013UsesRestoredEpochAfterRestartMemoryLoss(t *testing.T) {
	withFreshSingletonNode(t)

	keyHex := generateTestKeyHex(t)
	startResult := StartNode(startNodeJSON(t, keyHex))
	assertOk(t, parseJSON(t, startResult))

	const groupId = "ke013-restored-group"
	const restoredEpoch = 7
	restoredKeyMap := parseJSON(t, GenerateGroupKey())
	assertOk(t, restoredKeyMap)
	restoredKey := restoredKeyMap["groupKey"].(string)

	updateInput, _ := json.Marshal(map[string]interface{}{
		"groupId":  groupId,
		"groupKey": restoredKey,
		"keyEpoch": restoredEpoch,
	})
	updateMap := parseJSON(t, GroupUpdateKey(string(updateInput)))
	assertOk(t, updateMap)

	nextInput, _ := json.Marshal(map[string]string{"groupId": groupId})
	nextMap := parseJSON(t, GroupGenerateNextKey(string(nextInput)))
	assertOk(t, nextMap)

	nextEpoch, ok := nextMap["keyEpoch"].(float64)
	if !ok {
		t.Fatal("response missing keyEpoch")
	}
	if int(nextEpoch) != restoredEpoch+1 {
		t.Fatalf("expected restored next keyEpoch=%d, got %d", restoredEpoch+1, int(nextEpoch))
	}
	nextKey, ok := nextMap["groupKey"].(string)
	if !ok || nextKey == "" {
		t.Fatal("response missing non-empty groupKey")
	}

	nodeMu.Lock()
	storedAfterGenerate := singletonNode.GetGroupKeyInfo(groupId)
	nodeMu.Unlock()
	if storedAfterGenerate == nil {
		t.Fatal("expected stored key info after restored generateNextKey")
	}
	if storedAfterGenerate.Key != restoredKey {
		t.Fatalf("generateNextKey should not mutate restored key: got %q want %q", storedAfterGenerate.Key, restoredKey)
	}
	if storedAfterGenerate.KeyEpoch != restoredEpoch {
		t.Fatalf("generateNextKey should not mutate restored epoch: got %d want %d", storedAfterGenerate.KeyEpoch, restoredEpoch)
	}
}
