package presence

import (
	"context"
	"encoding/json"
	"time"

	"github.com/redis/go-redis/v9"
)

const (
	HeartbeatTTL  = 45 * time.Second
	EventsChannel = "tgdesk:events"
)

type Event struct {
	Type      string `json:"type"` // presence, suspend/resume, bind, telemetry
	TargetID  string `json:"target_id"`
	Payload   any    `json:"payload,omitempty"`
	Timestamp int64  `json:"timestamp"`
}

func presenceKey(deviceID string) string {
	return "presence:device:" + deviceID
}

// Heartbeat marks a device as online for HeartbeatTTL.
func Heartbeat(ctx context.Context, rdb *redis.Client, deviceID string) error {
	return rdb.Set(ctx, presenceKey(deviceID), "1", HeartbeatTTL).Err()
}

// IsOnline reports whether a device has a live heartbeat key.
func IsOnline(ctx context.Context, rdb *redis.Client, deviceID string) bool {
	n, err := rdb.Exists(ctx, presenceKey(deviceID)).Result()
	return err == nil && n > 0
}

// Clear removes the heartbeat key, forcing a device to read as offline immediately.
func Clear(ctx context.Context, rdb *redis.Client, deviceID string) error {
	return rdb.Del(ctx, presenceKey(deviceID)).Err()
}

func Publish(ctx context.Context, rdb *redis.Client, evt Event) error {
	evt.Timestamp = time.Now().Unix()
	b, err := json.Marshal(evt)
	if err != nil {
		return err
	}
	return rdb.Publish(ctx, EventsChannel, b).Err()
}

func Subscribe(ctx context.Context, rdb *redis.Client) *redis.PubSub {
	return rdb.Subscribe(ctx, EventsChannel)
}
