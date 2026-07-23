package main

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"errors"

	"golang.org/x/crypto/curve25519"
)

type wgKey [32]byte

func generateKey() (wgKey, error) {
	var priv wgKey
	if _, err := rand.Read(priv[:]); err != nil {
		return wgKey{}, err
	}
	priv[0] &= 248
	priv[31] &= 127
	priv[31] |= 64
	return priv, nil
}

func (k wgKey) public() wgKey {
	var pub [32]byte
	curve25519.ScalarBaseMult(&pub, (*[32]byte)(&k))
	return wgKey(pub)
}

func (k wgKey) base64() string { return base64.StdEncoding.EncodeToString(k[:]) }
func (k wgKey) hex() string    { return hex.EncodeToString(k[:]) }

func decodeBase64Key(s string) (wgKey, error) {
	var k wgKey
	raw, err := base64Decode(s)
	if err != nil || len(raw) != 32 {
		return wgKey{}, errors.New("chave inválida")
	}
	copy(k[:], raw)
	return k, nil
}

func base64Decode(s string) ([]byte, error) {
	return base64.StdEncoding.DecodeString(s)
}
