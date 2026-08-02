package main

import (
	"crypto/rand"
	"encoding/base64"

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
func (k wgKey) hex() string {
	const hextable = "0123456789abcdef"
	out := make([]byte, 64)
	for i, b := range k {
		out[i*2] = hextable[b>>4]
		out[i*2+1] = hextable[b&0x0f]
	}
	return string(out)
}
