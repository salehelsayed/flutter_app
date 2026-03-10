package main

import (
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"time"

	mcrypto "github.com/mknoon/go-mknoon/crypto"
	"github.com/mknoon/go-mknoon/identity"
	"github.com/mknoon/go-mknoon/node"
)

// peerState holds the running state of the test peer.
type peerState struct {
	node           *node.Node
	collector      *messageCollector
	identity       *identity.Identity
	privateKeyHex  string
	mlKemPublicKey string
	mlKemSecretKey string
}

var state = &peerState{}

// handleCommand dispatches a command and returns the result map.
func handleCommand(cmd string, params map[string]interface{}) map[string]interface{} {
	switch cmd {

	case "generate_identity":
		return cmdGenerateIdentity()

	case "restore_identity":
		return cmdRestoreIdentity(params)

	case "mlkem_keygen":
		return cmdMlKemKeygen()

	case "start":
		return cmdStart(params)

	case "stop":
		return cmdStop()

	case "status":
		return cmdStatus()

	case "wait_relay":
		return cmdWaitRelay(params)

	case "wait_circuit":
		return cmdWaitCircuit(params)

	case "register":
		return cmdRegister(params)

	case "discover":
		return cmdDiscover(params)

	case "dial":
		return cmdDial(params)

	case "send_v1":
		return cmdSendV1(params)

	case "send_v2":
		return cmdSendV2(params)

	case "send_raw":
		return cmdSendRaw(params)

	case "inbox_store_v1":
		return cmdInboxStoreV1(params)

	case "inbox_store_v2":
		return cmdInboxStoreV2(params)

	case "inbox_store_raw":
		return cmdInboxStoreRaw(params)

	case "inbox_retrieve":
		return cmdInboxRetrieve()

	case "get_messages":
		return cmdGetMessages()

	case "wait_message":
		return cmdWaitMessage(params)

	case "clear_messages":
		return cmdClearMessages()

	case "reconnect_relays":
		return cmdReconnectRelays()

	case "disconnect":
		return cmdDisconnect(params)

	case "media_upload":
		return cmdMediaUpload(params)

	case "media_download":
		return cmdMediaDownload(params)

	case "media_delete":
		return cmdMediaDelete(params)

	case "media_list":
		return cmdMediaList()

	case "profile_upload":
		return cmdProfileUpload(params)

	case "profile_download":
		return cmdProfileDownload(params)

	case "group_join":
		return cmdGroupJoin(params)

	case "group_leave":
		return cmdGroupLeave(params)

	case "group_publish":
		return cmdGroupPublish(params)

	case "group_inbox_store":
		return cmdGroupInboxStore(params)

	default:
		return errResult(fmt.Sprintf("unknown command: %s", cmd))
	}
}

func cmdGenerateIdentity() map[string]interface{} {
	id, err := identity.GenerateIdentity()
	if err != nil {
		return errResult(fmt.Sprintf("generate identity: %v", err))
	}
	state.identity = id

	// Convert base64 private key to hex for NodeConfig.
	privBytes, err := base64.StdEncoding.DecodeString(id.PrivateKey)
	if err != nil {
		return errResult(fmt.Sprintf("decode private key: %v", err))
	}
	state.privateKeyHex = hex.EncodeToString(privBytes)

	return okResult(map[string]interface{}{
		"peerId":     id.PeerId,
		"publicKey":  id.PublicKey,
		"privateKey": id.PrivateKey,
		"mnemonic12": id.Mnemonic12,
	})
}

func cmdRestoreIdentity(params map[string]interface{}) map[string]interface{} {
	mnemonic, _ := params["mnemonic12"].(string)
	if mnemonic == "" {
		return errResult("missing mnemonic12")
	}

	id, err := identity.RestoreIdentity(mnemonic)
	if err != nil {
		return errResult(fmt.Sprintf("restore identity: %v", err))
	}
	state.identity = id

	privBytes, err := base64.StdEncoding.DecodeString(id.PrivateKey)
	if err != nil {
		return errResult(fmt.Sprintf("decode private key: %v", err))
	}
	state.privateKeyHex = hex.EncodeToString(privBytes)

	return okResult(map[string]interface{}{
		"peerId":     id.PeerId,
		"publicKey":  id.PublicKey,
		"privateKey": id.PrivateKey,
		"mnemonic12": id.Mnemonic12,
	})
}

func cmdMlKemKeygen() map[string]interface{} {
	kp, err := mcrypto.MlKemKeygen()
	if err != nil {
		return errResult(fmt.Sprintf("mlkem keygen: %v", err))
	}
	state.mlKemPublicKey = kp.PublicKey
	state.mlKemSecretKey = kp.SecretKey

	return okResult(map[string]interface{}{
		"publicKey": kp.PublicKey,
		"secretKey": kp.SecretKey,
	})
}

func cmdStart(params map[string]interface{}) map[string]interface{} {
	if state.identity == nil {
		return errResult("no identity generated — call generate_identity first")
	}
	if state.node != nil {
		return errResult("node already started")
	}

	relay := node.RelayAddress()
	if r, ok := params["relayAddress"].(string); ok && r != "" {
		relay = r
	}

	relayAddresses := []string{relay}
	if addrs, ok := params["relayAddresses"].([]interface{}); ok {
		relayAddresses = nil
		for _, a := range addrs {
			if s, ok := a.(string); ok {
				relayAddresses = append(relayAddresses, s)
			}
		}
	}

	namespace := ""
	if ns, ok := params["namespace"].(string); ok {
		namespace = ns
	}

	autoRegister := false
	if ar, ok := params["autoRegister"].(bool); ok {
		autoRegister = ar
	}

	var featureFlags *node.FeatureFlags
	if rawFlags, ok := params["featureFlags"].(map[string]interface{}); ok {
		featureFlags = &node.FeatureFlags{
			EnableSharedRelayBackend:     boolFromMap(rawFlags, "enableSharedRelayBackend"),
			EnableMultiRelayRouting:      boolFromMap(rawFlags, "enableMultiRelayRouting"),
			EnableReservationAwareHealth: boolFromMap(rawFlags, "enableReservationAwareHealth"),
			EnableInPlaceRelayRecovery:   boolFromMap(rawFlags, "enableInPlaceRelayRecovery"),
			EnableResumeGroupRecovery:    boolFromMap(rawFlags, "enableResumeGroupRecovery"),
		}
	}

	state.collector = newMessageCollector()
	state.node = node.New(state.collector)

	cfg := node.NodeConfig{
		PrivateKeyHex:  state.privateKeyHex,
		RelayAddresses: relayAddresses,
		Namespace:      namespace,
		AutoRegister:   autoRegister,
		ListenPort:     0,
		FeatureFlags:   featureFlags,
	}

	nodeState, err := state.node.Start(cfg)
	if err != nil {
		state.node = nil
		state.collector = nil
		return errResult(fmt.Sprintf("start node: %v", err))
	}

	return okResult(map[string]interface{}{
		"peerId":    nodeState.PeerId,
		"addresses": nodeState.Addresses,
	})
}

func boolFromMap(values map[string]interface{}, key string) bool {
	raw, ok := values[key]
	if !ok {
		return false
	}
	value, ok := raw.(bool)
	return ok && value
}

func cmdStop() map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	if err := state.node.Stop(); err != nil {
		return errResult(fmt.Sprintf("stop: %v", err))
	}
	state.node = nil
	state.collector = nil
	return okResult(nil)
}

func cmdStatus() map[string]interface{} {
	if state.node == nil {
		return okResult(map[string]interface{}{
			"isStarted": false,
		})
	}
	return okResult(state.node.Status())
}

func cmdWaitRelay(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	timeoutSec := floatParam(params, "timeoutSec", 15)
	timeout := time.Duration(timeoutSec) * time.Second

	if err := state.node.WaitForRelayConnection(timeout); err != nil {
		return errResult(fmt.Sprintf("wait relay: %v", err))
	}
	return okResult(nil)
}

func cmdWaitCircuit(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	timeoutSec := floatParam(params, "timeoutSec", 15)
	timeout := time.Duration(timeoutSec) * time.Second

	// Poll for circuit address.
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		status := state.node.Status()
		if addrs, ok := status["circuitAddresses"].([]string); ok && len(addrs) > 0 {
			return okResult(map[string]interface{}{
				"circuitAddresses": addrs,
			})
		}
		time.Sleep(200 * time.Millisecond)
	}
	return errResult("timeout waiting for circuit address")
}

func cmdRegister(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	namespace, _ := params["namespace"].(string)
	if namespace == "" {
		namespace = state.node.Namespace()
	}

	if err := state.node.RendezvousRegister(namespace, nil); err != nil {
		return errResult(fmt.Sprintf("register: %v", err))
	}
	return okResult(map[string]interface{}{
		"namespace": namespace,
	})
}

func cmdDiscover(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	namespace, _ := params["namespace"].(string)
	if namespace == "" {
		return errResult("missing namespace")
	}

	peers, err := state.node.RendezvousDiscover(namespace, nil)
	if err != nil {
		return errResult(fmt.Sprintf("discover: %v", err))
	}

	peerList := make([]map[string]interface{}, 0, len(peers))
	for _, p := range peers {
		addrs := make([]string, 0, len(p.Addrs))
		for _, a := range p.Addrs {
			addrs = append(addrs, a.String())
		}
		peerList = append(peerList, map[string]interface{}{
			"peerId":    p.ID.String(),
			"addresses": addrs,
		})
	}

	return okResult(map[string]interface{}{
		"peers": peerList,
	})
}

func cmdDial(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	peerId, _ := params["peerId"].(string)
	if peerId == "" {
		return errResult("missing peerId")
	}

	var addresses []string
	if addrs, ok := params["addresses"].([]interface{}); ok {
		for _, a := range addrs {
			if s, ok := a.(string); ok {
				addresses = append(addresses, s)
			}
		}
	}

	if err := state.node.DialPeer(peerId, addresses); err != nil {
		return errResult(fmt.Sprintf("dial: %v", err))
	}
	return okResult(nil)
}

func cmdSendV1(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	if state.identity == nil {
		return errResult("no identity")
	}

	peerId, _ := params["peerId"].(string)
	text, _ := params["text"].(string)
	if peerId == "" || text == "" {
		return errResult("missing peerId or text")
	}

	username := state.identity.PeerId[:8]
	if u, ok := params["senderUsername"].(string); ok && u != "" {
		username = u
	}

	opts := make(map[string]interface{})
	if qid, ok := params["quotedMessageId"]; ok {
		opts["quotedMessageId"] = qid
	}
	if media, ok := params["media"]; ok {
		opts["media"] = media
	}
	if mid, ok := params["messageId"]; ok {
		opts["messageId"] = mid
	}

	envelope, msgID, err := buildV1Envelope(text, state.identity.PeerId, username, opts)
	if err != nil {
		return errResult(fmt.Sprintf("build v1: %v", err))
	}

	reply, acked, err := state.node.SendMessage(peerId, envelope, 0)
	if err != nil {
		return errResult(fmt.Sprintf("send: %v", err))
	}

	return okResult(map[string]interface{}{
		"messageId": msgID,
		"acked":     acked,
		"reply":     reply,
	})
}

func cmdSendV2(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	if state.identity == nil {
		return errResult("no identity")
	}

	peerId, _ := params["peerId"].(string)
	text, _ := params["text"].(string)
	recipientMlKemPK, _ := params["recipientMlKemPublicKey"].(string)

	if peerId == "" || text == "" || recipientMlKemPK == "" {
		return errResult("missing peerId, text, or recipientMlKemPublicKey")
	}

	username := state.identity.PeerId[:8]
	if u, ok := params["senderUsername"].(string); ok && u != "" {
		username = u
	}

	opts := make(map[string]interface{})
	if qid, ok := params["quotedMessageId"]; ok {
		opts["quotedMessageId"] = qid
	}
	if media, ok := params["media"]; ok {
		opts["media"] = media
	}
	if mid, ok := params["messageId"]; ok {
		opts["messageId"] = mid
	}

	envelope, msgID, err := buildV2Envelope(text, state.identity.PeerId, username, recipientMlKemPK, opts)
	if err != nil {
		return errResult(fmt.Sprintf("build v2: %v", err))
	}

	reply, acked, err := state.node.SendMessage(peerId, envelope, 0)
	if err != nil {
		return errResult(fmt.Sprintf("send: %v", err))
	}

	return okResult(map[string]interface{}{
		"messageId": msgID,
		"acked":     acked,
		"reply":     reply,
	})
}

func cmdSendRaw(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}

	peerId, _ := params["peerId"].(string)
	raw, _ := params["raw"].(string)
	if peerId == "" || raw == "" {
		return errResult("missing peerId or raw")
	}

	reply, acked, err := state.node.SendMessage(peerId, raw, 0)
	if err != nil {
		return errResult(fmt.Sprintf("send raw: %v", err))
	}

	return okResult(map[string]interface{}{
		"acked": acked,
		"reply": reply,
	})
}

func cmdInboxStoreV1(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	if state.identity == nil {
		return errResult("no identity")
	}

	peerId, _ := params["peerId"].(string)
	text, _ := params["text"].(string)
	if peerId == "" || text == "" {
		return errResult("missing peerId or text")
	}

	username := state.identity.PeerId[:8]
	if u, ok := params["senderUsername"].(string); ok && u != "" {
		username = u
	}

	opts := make(map[string]interface{})
	if qid, ok := params["quotedMessageId"]; ok {
		opts["quotedMessageId"] = qid
	}
	if media, ok := params["media"]; ok {
		opts["media"] = media
	}
	if mid, ok := params["messageId"]; ok {
		opts["messageId"] = mid
	}

	envelope, msgID, err := buildV1Envelope(text, state.identity.PeerId, username, opts)
	if err != nil {
		return errResult(fmt.Sprintf("build v1: %v", err))
	}

	if err := state.node.InboxStore(peerId, envelope); err != nil {
		return errResult(fmt.Sprintf("inbox store: %v", err))
	}

	return okResult(map[string]interface{}{
		"messageId": msgID,
	})
}

func cmdInboxStoreV2(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	if state.identity == nil {
		return errResult("no identity")
	}

	peerId, _ := params["peerId"].(string)
	text, _ := params["text"].(string)
	recipientMlKemPK, _ := params["recipientMlKemPublicKey"].(string)

	if peerId == "" || text == "" || recipientMlKemPK == "" {
		return errResult("missing peerId, text, or recipientMlKemPublicKey")
	}

	username := state.identity.PeerId[:8]
	if u, ok := params["senderUsername"].(string); ok && u != "" {
		username = u
	}

	opts := make(map[string]interface{})
	if qid, ok := params["quotedMessageId"]; ok {
		opts["quotedMessageId"] = qid
	}
	if mid, ok := params["messageId"]; ok {
		opts["messageId"] = mid
	}

	envelope, msgID, err := buildV2Envelope(text, state.identity.PeerId, username, recipientMlKemPK, opts)
	if err != nil {
		return errResult(fmt.Sprintf("build v2: %v", err))
	}

	if err := state.node.InboxStore(peerId, envelope); err != nil {
		return errResult(fmt.Sprintf("inbox store: %v", err))
	}

	return okResult(map[string]interface{}{
		"messageId": msgID,
	})
}

func cmdInboxStoreRaw(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}

	peerId, _ := params["peerId"].(string)
	envelope, _ := params["envelope"].(string)
	if peerId == "" || envelope == "" {
		return errResult("missing peerId or envelope")
	}

	if err := state.node.InboxStore(peerId, envelope); err != nil {
		return errResult(fmt.Sprintf("inbox store raw: %v", err))
	}

	return okResult(nil)
}

func cmdInboxRetrieve() map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}

	msgs, err := state.node.InboxRetrieve()
	if err != nil {
		return errResult(fmt.Sprintf("inbox retrieve: %v", err))
	}

	list := make([]map[string]interface{}, 0, len(msgs))
	for _, m := range msgs {
		list = append(list, map[string]interface{}{
			"from":      m.From,
			"message":   m.Message,
			"timestamp": m.Timestamp,
		})
	}

	return okResult(map[string]interface{}{
		"messages": list,
		"count":    len(list),
	})
}

func cmdGetMessages() map[string]interface{} {
	if state.collector == nil {
		return okResult(map[string]interface{}{
			"messages": []incomingMessage{},
			"count":    0,
		})
	}

	msgs := state.collector.getMessages()
	return okResult(map[string]interface{}{
		"messages": msgs,
		"count":    len(msgs),
	})
}

func cmdWaitMessage(params map[string]interface{}) map[string]interface{} {
	if state.collector == nil {
		return errResult("no collector — node not started")
	}

	fromPeerId, _ := params["fromPeerId"].(string)
	timeoutSec := floatParam(params, "timeoutSec", 30)
	timeout := time.Duration(timeoutSec) * time.Second

	msg := state.collector.waitMessage(fromPeerId, timeout)
	if msg == nil {
		return errResult("timeout waiting for message")
	}

	return okResult(map[string]interface{}{
		"from":      msg.From,
		"to":        msg.To,
		"content":   msg.Content,
		"timestamp": msg.Timestamp,
	})
}

func cmdClearMessages() map[string]interface{} {
	if state.collector != nil {
		state.collector.clearMessages()
	}
	return okResult(nil)
}

func cmdReconnectRelays() map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	result, err := state.node.ReconnectRelays()
	if err != nil {
		return errResult(fmt.Sprintf("reconnect relays: %v", err))
	}
	_ = result
	return okResult(nil)
}

func cmdDisconnect(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	peerId, _ := params["peerId"].(string)
	if peerId == "" {
		return errResult("missing peerId")
	}
	if err := state.node.DisconnectPeer(peerId); err != nil {
		return errResult(fmt.Sprintf("disconnect: %v", err))
	}
	return okResult(nil)
}

func cmdMediaUpload(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	id, _ := params["id"].(string)
	toPeerId, _ := params["toPeerId"].(string)
	mime, _ := params["mime"].(string)
	filePath, _ := params["filePath"].(string)
	if id == "" || toPeerId == "" || mime == "" || filePath == "" {
		return errResult("missing id, toPeerId, mime, or filePath")
	}
	if err := state.node.MediaUpload(id, toPeerId, mime, filePath, nil); err != nil {
		return errResult(fmt.Sprintf("media upload: %v", err))
	}
	return okResult(map[string]interface{}{
		"id": id,
	})
}

func cmdMediaDownload(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	id, _ := params["id"].(string)
	outputPath, _ := params["outputPath"].(string)
	if id == "" || outputPath == "" {
		return errResult("missing id or outputPath")
	}
	mime, size, err := state.node.MediaDownload(id, outputPath)
	if err != nil {
		return errResult(fmt.Sprintf("media download: %v", err))
	}
	return okResult(map[string]interface{}{
		"mime": mime,
		"size": size,
	})
}

func cmdMediaDelete(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	id, _ := params["id"].(string)
	if id == "" {
		return errResult("missing id")
	}
	if err := state.node.MediaDelete(id); err != nil {
		return errResult(fmt.Sprintf("media delete: %v", err))
	}
	return okResult(nil)
}

func cmdMediaList() map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	blobs, err := state.node.MediaList()
	if err != nil {
		return errResult(fmt.Sprintf("media list: %v", err))
	}
	list := make([]map[string]interface{}, 0, len(blobs))
	for _, b := range blobs {
		list = append(list, map[string]interface{}{
			"id":   b.ID,
			"from": b.From,
			"mime": b.Mime,
			"size": b.Size,
		})
	}
	return okResult(map[string]interface{}{
		"blobs": list,
	})
}

func cmdProfileUpload(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	mime, _ := params["mime"].(string)
	filePath, _ := params["filePath"].(string)
	if mime == "" || filePath == "" {
		return errResult("missing mime or filePath")
	}
	if err := state.node.ProfileUpload(mime, filePath); err != nil {
		return errResult(fmt.Sprintf("profile upload: %v", err))
	}
	return okResult(nil)
}

func cmdProfileDownload(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	ownerPeerId, _ := params["ownerPeerId"].(string)
	outputPath, _ := params["outputPath"].(string)
	if ownerPeerId == "" || outputPath == "" {
		return errResult("missing ownerPeerId or outputPath")
	}
	mime, size, err := state.node.ProfileDownload(ownerPeerId, outputPath)
	if err != nil {
		return errResult(fmt.Sprintf("profile download: %v", err))
	}
	return okResult(map[string]interface{}{
		"mime": mime,
		"size": size,
	})
}

func cmdGroupJoin(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}

	groupId, _ := params["groupId"].(string)
	groupKey, _ := params["groupKey"].(string)
	keyEpoch := intParam(params, "keyEpoch", 1)
	rawConfig, ok := params["groupConfig"]

	if groupId == "" || groupKey == "" || !ok {
		return errResult("missing groupId, groupKey, or groupConfig")
	}

	configBytes, err := json.Marshal(rawConfig)
	if err != nil {
		return errResult(fmt.Sprintf("marshal groupConfig: %v", err))
	}

	var config node.GroupConfig
	if err := json.Unmarshal(configBytes, &config); err != nil {
		return errResult(fmt.Sprintf("unmarshal groupConfig: %v", err))
	}

	keyInfo := &node.GroupKeyInfo{
		Key:      groupKey,
		KeyEpoch: keyEpoch,
	}

	if err := state.node.JoinGroupTopic(groupId, &config, keyInfo); err != nil {
		return errResult(fmt.Sprintf("group join: %v", err))
	}

	return okResult(nil)
}

func cmdGroupLeave(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}

	groupId, _ := params["groupId"].(string)
	if groupId == "" {
		return errResult("missing groupId")
	}

	if err := state.node.LeaveGroupTopic(groupId); err != nil {
		return errResult(fmt.Sprintf("group leave: %v", err))
	}

	return okResult(nil)
}

func cmdGroupPublish(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	if state.identity == nil {
		return errResult("no identity")
	}

	groupId, _ := params["groupId"].(string)
	text, _ := params["text"].(string)
	if groupId == "" || text == "" {
		return errResult("missing groupId or text")
	}

	senderUsername := state.identity.PeerId[:8]
	if u, ok := params["senderUsername"].(string); ok && u != "" {
		senderUsername = u
	}

	messageId, _ := params["messageId"].(string)

	msgId, err := state.node.PublishGroupMessage(
		groupId,
		state.identity.PrivateKey,
		state.identity.PeerId,
		state.identity.PublicKey,
		senderUsername,
		text,
		messageId,
		nil,
	)
	if err != nil {
		return errResult(fmt.Sprintf("group publish: %v", err))
	}

	return okResult(map[string]interface{}{
		"messageId": msgId,
	})
}

func cmdGroupInboxStore(params map[string]interface{}) map[string]interface{} {
	if state.node == nil {
		return errResult("node not started")
	}
	if state.identity == nil {
		return errResult("no identity")
	}

	groupId, _ := params["groupId"].(string)
	text, _ := params["text"].(string)
	if groupId == "" || text == "" {
		return errResult("missing groupId or text")
	}

	senderUsername := state.identity.PeerId[:8]
	if u, ok := params["senderUsername"].(string); ok && u != "" {
		senderUsername = u
	}

	messageId, _ := params["messageId"].(string)
	if messageId == "" {
		messageId = fmt.Sprintf("%s-%d", state.identity.PeerId, time.Now().UnixNano())
	}

	timestamp, _ := params["timestamp"].(string)
	if timestamp == "" {
		timestamp = time.Now().UTC().Format(time.RFC3339Nano)
	}

	keyEpoch := intParam(params, "keyEpoch", 0)

	payloadBytes, err := json.Marshal(map[string]interface{}{
		"groupId":        groupId,
		"senderId":       state.identity.PeerId,
		"senderUsername": senderUsername,
		"keyEpoch":       keyEpoch,
		"text":           text,
		"timestamp":      timestamp,
		"messageId":      messageId,
	})
	if err != nil {
		return errResult(fmt.Sprintf("marshal group inbox payload: %v", err))
	}

	if err := state.node.GroupInboxStore(groupId, string(payloadBytes)); err != nil {
		return errResult(fmt.Sprintf("group inbox store: %v", err))
	}

	return okResult(map[string]interface{}{
		"messageId": messageId,
	})
}

// --- helpers ---

func okResult(result map[string]interface{}) map[string]interface{} {
	if result == nil {
		return map[string]interface{}{"ok": true}
	}
	result["ok"] = true
	return result
}

func errResult(msg string) map[string]interface{} {
	return map[string]interface{}{
		"ok":           false,
		"errorMessage": msg,
	}
}

func floatParam(params map[string]interface{}, key string, defaultVal float64) float64 {
	if v, ok := params[key].(float64); ok {
		return v
	}
	return defaultVal
}

func intParam(params map[string]interface{}, key string, defaultVal int) int {
	if v, ok := params[key].(float64); ok {
		return int(v)
	}
	return defaultVal
}
