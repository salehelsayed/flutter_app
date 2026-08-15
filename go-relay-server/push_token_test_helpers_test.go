package main

func lookupTokenForTest(backend PushTokenBackend, peerID string) *tokenEntry {
	route, err := backend.LookupRoute(peerID)
	if err != nil || route == nil {
		return nil
	}
	target, err := backend.ResolveRoute(*route)
	if err != nil || target == nil {
		return nil
	}
	return &tokenEntry{
		Token:        target.Token,
		Platform:     target.Platform,
		Capabilities: append([]string(nil), target.Route.Capabilities...),
	}
}

// LookupToken is retained only in test builds while preservation tests migrate
// their assertions from the removed production token lookup to route resolution.
func (s *memoryPushTokenStore) LookupToken(peerID string) *tokenEntry {
	return lookupTokenForTest(s, peerID)
}

func (b *redisPushTokenBackend) LookupToken(peerID string) *tokenEntry {
	return lookupTokenForTest(b, peerID)
}
