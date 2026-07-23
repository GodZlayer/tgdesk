package wg

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"errors"

	"golang.org/x/crypto/curve25519"
)

type Key [32]byte

func GenerateKey() (Key, error) {
	var priv Key
	if _, err := rand.Read(priv[:]); err != nil {
		return Key{}, err
	}
	priv[0] &= 248
	priv[31] &= 127
	priv[31] |= 64
	return priv, nil
}

func (k Key) Public() Key {
	var pub [32]byte
	curve25519.ScalarBaseMult(&pub, (*[32]byte)(&k))
	return Key(pub)
}

func (k Key) Base64() string { return base64.StdEncoding.EncodeToString(k[:]) }
func (k Key) Hex() string    { return hex.EncodeToString(k[:]) }

func KeyFromBase64(s string) (Key, error) {
	b, err := base64.StdEncoding.DecodeString(s)
	if err != nil || len(b) != 32 {
		return Key{}, errors.New("chave WireGuard base64 inválida")
	}
	var k Key
	copy(k[:], b)
	return k, nil
}
