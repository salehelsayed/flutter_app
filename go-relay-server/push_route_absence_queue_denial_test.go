package main

import (
	"context"
	"testing"

	"github.com/redis/go-redis/v9"
)

// Replace only the optional marker command with an invalid-arity DBSIZE. Redis
// itself rejects it while queuing MULTI, rather than a hook merely reporting
// an error after EXEC has already succeeded. This is queue-rejection coverage,
// not an ACL integration test.
type missingRouteQueueDenialHook struct {
	key           string
	fired         int
	transactional bool
}

func (*missingRouteQueueDenialHook) DialHook(next redis.DialHook) redis.DialHook { return next }

func (hook *missingRouteQueueDenialHook) reject(command redis.Cmder) {
	args := command.Args()
	if len(args) >= 2 && args[1] == hook.key {
		args[0] = "dbsize"
		hook.fired++
	}
}

func (hook *missingRouteQueueDenialHook) ProcessHook(next redis.ProcessHook) redis.ProcessHook {
	return func(ctx context.Context, command redis.Cmder) error {
		hook.reject(command)
		return next(ctx, command)
	}
}

func (hook *missingRouteQueueDenialHook) ProcessPipelineHook(next redis.ProcessPipelineHook) redis.ProcessPipelineHook {
	return func(ctx context.Context, commands []redis.Cmder) error {
		before := hook.fired
		for _, command := range commands {
			hook.reject(command)
		}
		if hook.fired > before {
			hook.transactional = true
		}
		return next(ctx, commands)
	}
}

func TestPushMissingRouteQueueDenialPreservesPrimaryMutation(t *testing.T) {
	for _, kind := range []string{"redis_legacy", "redis_encrypted"} {
		for _, operation := range []string{"register", "unregister", "revoke"} {
			t.Run(kind+"/"+operation, func(t *testing.T) {
				backend := missingRouteBackend(t, kind).(*redisPushTokenBackend)
				if err := backend.RegisterToken("route-peer", "token-a", "ios"); err != nil {
					t.Fatal(err)
				}
				lease := plan367Route(t, backend, "route-peer")
				hook := &missingRouteQueueDenialHook{key: backend.absenceKey("route-peer")}
				backend.client.AddHook(hook)
				var err error
				switch operation {
				case "register":
					err = backend.RegisterToken("route-peer", "token-b", "ios")
				case "unregister":
					err = backend.UnregisterToken("route-peer")
				case "revoke":
					var revoked bool
					revoked, err = backend.RevokeIfCurrent(lease)
					if !revoked {
						t.Error("diagnostic denial prevented successful primary revoke")
					}
				}
				if hook.fired == 0 {
					t.Fatal("diagnostic denial was not exercised")
				}
				t.Logf("diagnostic rejection inside transaction=%v", hook.transactional)
				if err != nil {
					t.Errorf("optional diagnostic denial changed primary result: %v", err)
				}
				route, lookupErr := backend.LookupRoute("route-peer")
				if lookupErr != nil {
					t.Fatal(lookupErr)
				}
				if operation == "register" {
					if route == nil {
						t.Fatal("diagnostic denial prevented primary registration")
					}
					target := plan367Target(t, backend, *route)
					t.Logf("primary applied=%v", target.Token == "token-b")
					if target.Token != "token-b" {
						t.Error("diagnostic denial prevented primary token rotation")
					}
				} else {
					t.Logf("primary applied=%v", route == nil)
					if route != nil {
						t.Error("diagnostic denial left primary route registered")
					}
				}
			})
		}
	}
}
