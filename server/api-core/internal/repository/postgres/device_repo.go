package postgres

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"tgdesk/api-core/internal/models"
	"tgdesk/api-core/internal/repository"
)

type PostgresDeviceRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresDeviceRepository(pool *pgxpool.Pool) repository.DeviceRepository {
	return &PostgresDeviceRepository{pool: pool}
}

func (r *PostgresDeviceRepository) GetDevice(ctx context.Context, id string) (*models.Device, error) {
	var d models.Device
	query := `
		SELECT id, network_id, subnetwork_id, hostname, display_name, mac, wg_pubkey, role, state,
		       pairing_code, device_token, rustdesk_id, last_seen_at, created_at, updated_at,
		       remote_ready, files_ready, health_level
		FROM devices WHERE id = $1`

	err := r.pool.QueryRow(ctx, query, id).Scan(
		&d.ID, &d.NetworkID, &d.SubnetworkID, &d.Hostname, &d.DisplayName, &d.MAC, &d.WGPubkey,
		&d.Role, &d.State, &d.PairingCode, &d.DeviceToken, &d.RustdeskID, &d.LastSeenAt,
		&d.CreatedAt, &d.UpdatedAt, &d.RemoteReady, &d.FilesReady, &d.HealthLevel,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("device not found")
		}
		return nil, err
	}

	return &d, nil
}

func (r *PostgresDeviceRepository) GetDeviceByMAC(ctx context.Context, mac string) (*models.Device, error) {
	var d models.Device
	query := `
		SELECT id, network_id, subnetwork_id, hostname, display_name, mac, wg_pubkey, role, state,
		       pairing_code, device_token, rustdesk_id, last_seen_at, created_at, updated_at,
		       remote_ready, files_ready, health_level
		FROM devices WHERE lower(btrim(mac)) = lower($1)
		ORDER BY created_at LIMIT 1`

	err := r.pool.QueryRow(ctx, query, strings.TrimSpace(mac)).Scan(
		&d.ID, &d.NetworkID, &d.SubnetworkID, &d.Hostname, &d.DisplayName, &d.MAC, &d.WGPubkey,
		&d.Role, &d.State, &d.PairingCode, &d.DeviceToken, &d.RustdeskID, &d.LastSeenAt,
		&d.CreatedAt, &d.UpdatedAt, &d.RemoteReady, &d.FilesReady, &d.HealthLevel,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.New("device not found")
		}
		return nil, err
	}

	return &d, nil
}

func (r *PostgresDeviceRepository) GetDevicesByNetwork(ctx context.Context, networkID string) ([]*models.Device, error) {
	return r.listDevices(ctx, &repository.DeviceFilter{
		NetworkID: &networkID,
	})
}

func (r *PostgresDeviceRepository) GetDevicesBySubnetwork(ctx context.Context, subnetworkID string) ([]*models.Device, error) {
	return r.listDevices(ctx, &repository.DeviceFilter{
		SubnetworkID: &subnetworkID,
	})
}

func (r *PostgresDeviceRepository) ListDevices(ctx context.Context, filter *repository.DeviceFilter) ([]*models.Device, error) {
	if filter == nil {
		filter = &repository.DeviceFilter{}
	}
	return r.listDevices(ctx, filter)
}

func (r *PostgresDeviceRepository) listDevices(ctx context.Context, filter *repository.DeviceFilter) ([]*models.Device, error) {
	query := `
		SELECT id, network_id, subnetwork_id, hostname, display_name, mac, wg_pubkey, role, state,
		       pairing_code, device_token, rustdesk_id, last_seen_at, created_at, updated_at,
		       remote_ready, files_ready, health_level
		FROM devices WHERE 1=1`

	var args []any
	argIdx := 1

	if filter.NetworkID != nil && *filter.NetworkID != "" {
		query += fmt.Sprintf(` AND network_id = $%d`, argIdx)
		args = append(args, *filter.NetworkID)
		argIdx++
	}

	if filter.SubnetworkID != nil && *filter.SubnetworkID != "" {
		query += fmt.Sprintf(` AND subnetwork_id = $%d`, argIdx)
		args = append(args, *filter.SubnetworkID)
		argIdx++
	}

	if filter.Status != nil && *filter.Status != "" {
		query += fmt.Sprintf(` AND state = $%d`, argIdx)
		args = append(args, *filter.Status)
		argIdx++
	}

	query += ` ORDER BY created_at`

	if filter.Limit > 0 {
		query += fmt.Sprintf(` LIMIT $%d`, argIdx)
		args = append(args, filter.Limit)
		argIdx++
	}

	if filter.Offset > 0 {
		query += fmt.Sprintf(` OFFSET $%d`, argIdx)
		args = append(args, filter.Offset)
	}

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var devices []*models.Device
	for rows.Next() {
		var d models.Device
		if err := rows.Scan(
			&d.ID, &d.NetworkID, &d.SubnetworkID, &d.Hostname, &d.DisplayName, &d.MAC, &d.WGPubkey,
			&d.Role, &d.State, &d.PairingCode, &d.DeviceToken, &d.RustdeskID, &d.LastSeenAt,
			&d.CreatedAt, &d.UpdatedAt, &d.RemoteReady, &d.FilesReady, &d.HealthLevel,
		); err != nil {
			return nil, err
		}
		devices = append(devices, &d)
	}

	return devices, rows.Err()
}

func (r *PostgresDeviceRepository) CreateDevice(ctx context.Context, device *models.Device) error {
	query := `
		INSERT INTO devices (hostname, mac, role, state, pairing_code)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, device_token, created_at, updated_at`

	err := r.pool.QueryRow(ctx, query,
		device.Hostname, device.MAC, device.Role, device.State, device.PairingCode,
	).Scan(&device.ID, &device.DeviceToken, &device.CreatedAt, &device.UpdatedAt)

	return err
}

func (r *PostgresDeviceRepository) UpdateDevice(ctx context.Context, device *models.Device) error {
	query := `
		UPDATE devices
		SET hostname = $1, display_name = $2, role = $3, state = $4,
		    network_id = $5, subnetwork_id = $6, wg_pubkey = $7,
		    rustdesk_id = $8, remote_ready = $9, files_ready = $10,
		    health_level = $11, updated_at = now()
		WHERE id = $12`

	_, err := r.pool.Exec(ctx, query,
		device.Hostname, device.DisplayName, device.Role, device.State,
		device.NetworkID, device.SubnetworkID, device.WGPubkey,
		device.RustdeskID, device.RemoteReady, device.FilesReady,
		device.HealthLevel, device.ID,
	)

	return err
}

func (r *PostgresDeviceRepository) DeleteDevice(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx, `DELETE FROM devices WHERE id = $1`, id)
	return err
}

func (r *PostgresDeviceRepository) GetDeviceToken(ctx context.Context, id string) (string, error) {
	var token string
	err := r.pool.QueryRow(ctx, `SELECT device_token FROM devices WHERE id = $1`, id).Scan(&token)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", errors.New("device not found")
		}
		return "", err
	}
	return token, nil
}

func (r *PostgresDeviceRepository) UpdateDeviceLastSeen(ctx context.Context, id string) error {
	_, err := r.pool.Exec(ctx, `UPDATE devices SET last_seen_at = now() WHERE id = $1`, id)
	return err
}

func (r *PostgresDeviceRepository) GetDevicesWithPresence(ctx context.Context, filter *repository.DeviceFilter, presenceMap map[string]string) ([]*models.Device, error) {
	devices, err := r.ListDevices(ctx, filter)
	if err != nil {
		return nil, err
	}

	for _, d := range devices {
		if presence, ok := presenceMap[d.ID]; ok {
			d.Presence = presence
		}
	}

	return devices, nil
}
