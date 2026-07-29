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

type Capabilities struct {
	RemoteReady bool `json:"remote_ready"`
	FilesReady  bool `json:"files_ready"`
}

func presenceKey(deviceID string) string {
	return "presence:device:" + deviceID
}

func capabilitiesKey(deviceID string) string {
	return "capabilities:device:" + deviceID
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

func SetCapabilities(ctx context.Context, rdb *redis.Client, deviceID string, capabilities Capabilities) error {
	raw, err := json.Marshal(capabilities)
	if err != nil {
		return err
	}
	return rdb.Set(ctx, capabilitiesKey(deviceID), raw, HeartbeatTTL).Err()
}

func GetCapabilities(ctx context.Context, rdb *redis.Client, deviceID string) Capabilities {
	raw, err := rdb.Get(ctx, capabilitiesKey(deviceID)).Bytes()
	if err != nil {
		return Capabilities{}
	}
	var capabilities Capabilities
	if json.Unmarshal(raw, &capabilities) != nil {
		return Capabilities{}
	}
	return capabilities
}

// Clear removes the heartbeat key, forcing a device to read as offline immediately.
func Clear(ctx context.Context, rdb *redis.Client, deviceID string) error {
	return rdb.Del(ctx, presenceKey(deviceID), capabilitiesKey(deviceID)).Err()
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
