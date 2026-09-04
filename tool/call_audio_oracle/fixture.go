package callaudiooracle

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
)

const payloadHashDomain = "mknoon.known-opus-rtp-payload-sequence.v1"

func loadKnownFixture(path string) (knownFixture, error) {
	var fixture knownFixture
	encoded, err := os.ReadFile(path)
	if err != nil || len(encoded) == 0 {
		return fixture, errFixtureDocument
	}
	fileDigest := sha256.Sum256(encoded)
	fixture.fileDigestHex = hex.EncodeToString(fileDigest[:])

	provenanceFile, err := os.Open(provenancePathForFixture(path))
	if err != nil {
		return knownFixture{}, errFixtureDocument
	}
	defer provenanceFile.Close()
	var provenance fixtureProvenance
	if err := decodeStrictJSON(
		provenanceFile,
		maximumPrivateJSONBytes,
		&provenance,
	); err != nil {
		return knownFixture{}, errFixtureDocument
	}
	if provenance.Schema != fixtureSchema ||
		provenance.File != filepath.Base(path) ||
		provenance.License != "CC0-1.0" ||
		provenance.Codec != "audio/opus" ||
		provenance.SampleRateHz != 48000 || provenance.Channels != 1 ||
		provenance.FrameDurationMs != 20 ||
		provenance.PayloadHashDomain != payloadHashDomain ||
		provenance.RTPPayloadCount <= 0 ||
		!validLowerHexSHA256(provenance.FileSHA256) ||
		!validLowerHexSHA256(provenance.RTPPayloadSequenceSHA256) ||
		provenance.GenerationFormula == "" || provenance.Generator == "" ||
		provenance.GeneratorVersion == "" ||
		provenance.GeneratedAtSourceEpochUTC == "" {
		return knownFixture{}, errFixtureDocument
	}
	if provenance.FileSHA256 != knownFixtureSHA256 ||
		provenance.RTPPayloadSequenceSHA256 != knownPayloadSequenceSHA256 ||
		provenance.FileSHA256 != fixture.fileDigestHex {
		return knownFixture{}, errFixtureDigest
	}

	packets, err := parseOpusOgg(encoded)
	if err != nil || len(packets) != provenance.RTPPayloadCount {
		return knownFixture{}, errFixtureDocument
	}
	fixture.payloads = packets
	fixture.payloadDigest = hashPayloadSequence(packets)
	if hex.EncodeToString(fixture.payloadDigest[:]) != knownPayloadSequenceSHA256 {
		return knownFixture{}, errFixtureDigest
	}
	return fixture, nil
}

func parseOpusOgg(encoded []byte) ([][]byte, error) {
	reader := bytes.NewReader(encoded)
	var (
		logicalPackets [][]byte
		partial        []byte
		streamSerial   uint32
		pageSequence   uint32
		seenPage       bool
		seenEnd        bool
	)
	for reader.Len() > 0 {
		if seenEnd {
			return nil, errFixtureDocument
		}
		header := make([]byte, 27)
		if _, err := io.ReadFull(reader, header); err != nil ||
			!bytes.Equal(header[:4], []byte("OggS")) || header[4] != 0 {
			return nil, errFixtureDocument
		}
		headerType := header[5]
		serial := binary.LittleEndian.Uint32(header[14:18])
		sequence := binary.LittleEndian.Uint32(header[18:22])
		segmentCount := int(header[26])
		segments := make([]byte, segmentCount)
		if _, err := io.ReadFull(reader, segments); err != nil {
			return nil, errFixtureDocument
		}
		payloadLength := 0
		for _, segmentLength := range segments {
			payloadLength += int(segmentLength)
		}
		pagePayload := make([]byte, payloadLength)
		if _, err := io.ReadFull(reader, pagePayload); err != nil {
			return nil, errFixtureDocument
		}
		wholePage := append(append(append([]byte(nil), header...), segments...), pagePayload...)
		if !validOggCRC(wholePage) {
			return nil, errFixtureDigest
		}

		if !seenPage {
			if headerType&0x02 == 0 || headerType&0x01 != 0 || sequence != 0 {
				return nil, errFixtureDocument
			}
			streamSerial = serial
			pageSequence = sequence
			seenPage = true
		} else if serial != streamSerial || sequence != pageSequence+1 ||
			(headerType&0x01 == 0) != (len(partial) == 0) {
			return nil, errFixtureDocument
		} else {
			pageSequence = sequence
		}

		cursor := 0
		for _, segmentLengthByte := range segments {
			segmentLength := int(segmentLengthByte)
			partial = append(partial, pagePayload[cursor:cursor+segmentLength]...)
			cursor += segmentLength
			if segmentLength < 255 {
				logicalPackets = append(logicalPackets, append([]byte(nil), partial...))
				partial = partial[:0]
			}
		}
		seenEnd = headerType&0x04 != 0
	}
	if !seenPage || !seenEnd || len(partial) != 0 || len(logicalPackets) < 3 ||
		!bytes.HasPrefix(logicalPackets[0], []byte("OpusHead")) ||
		!bytes.HasPrefix(logicalPackets[1], []byte("OpusTags")) ||
		!validOpusHead(logicalPackets[0]) {
		return nil, errFixtureDocument
	}
	return clonePayloads(logicalPackets[2:]), nil
}

func validOpusHead(header []byte) bool {
	return len(header) >= 19 && header[8] == 1 && header[9] == 1 &&
		binary.LittleEndian.Uint32(header[12:16]) == 48000 && header[18] == 0
}

func clonePayloads(payloads [][]byte) [][]byte {
	clone := make([][]byte, len(payloads))
	for index, payload := range payloads {
		clone[index] = append([]byte(nil), payload...)
	}
	return clone
}

func hashPayloadSequence(payloads [][]byte) [sha256.Size]byte {
	hash := sha256.New()
	_, _ = hash.Write([]byte(payloadHashDomain))
	_, _ = hash.Write([]byte{0})
	var framed [8]byte
	for index, payload := range payloads {
		binary.BigEndian.PutUint32(framed[:4], uint32(index))
		binary.BigEndian.PutUint32(framed[4:], uint32(len(payload)))
		_, _ = hash.Write(framed[:])
		_, _ = hash.Write(payload)
	}
	var digest [sha256.Size]byte
	copy(digest[:], hash.Sum(nil))
	return digest
}

func validOggCRC(page []byte) bool {
	if len(page) < 27 {
		return false
	}
	want := binary.LittleEndian.Uint32(page[22:26])
	var crc uint32
	for index, value := range page {
		if index >= 22 && index < 26 {
			value = 0
		}
		crc = (crc << 8) ^ oggCRCTable[byte(crc>>24)^value]
	}
	return crc == want
}

var oggCRCTable = func() [256]uint32 {
	var table [256]uint32
	for index := range table {
		value := uint32(index) << 24
		for range 8 {
			if value&0x80000000 != 0 {
				value = (value << 1) ^ 0x04c11db7
			} else {
				value <<= 1
			}
		}
		table[index] = value
	}
	return table
}()

func fixtureProvenanceJSON(
	fixturePath string,
	generationFormula string,
	generatorVersion string,
	generatedAt string,
) ([]byte, error) {
	encoded, err := os.ReadFile(fixturePath)
	if err != nil {
		return nil, err
	}
	payloads, err := parseOpusOgg(encoded)
	if err != nil {
		return nil, err
	}
	fileDigest := sha256.Sum256(encoded)
	payloadDigest := hashPayloadSequence(payloads)
	provenance := fixtureProvenance{
		Schema:                    fixtureSchema,
		File:                      filepath.Base(fixturePath),
		FileSHA256:                hex.EncodeToString(fileDigest[:]),
		License:                   "CC0-1.0",
		Codec:                     "audio/opus",
		SampleRateHz:              48000,
		Channels:                  1,
		FrameDurationMs:           20,
		RTPPayloadCount:           len(payloads),
		RTPPayloadSequenceSHA256:  hex.EncodeToString(payloadDigest[:]),
		PayloadHashDomain:         payloadHashDomain,
		GenerationFormula:         generationFormula,
		Generator:                 "FFmpeg/libopus",
		GeneratorVersion:          generatorVersion,
		GeneratedAtSourceEpochUTC: generatedAt,
	}
	return json.MarshalIndent(provenance, "", "  ")
}
