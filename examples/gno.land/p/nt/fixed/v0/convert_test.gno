package fixed

import (
	"strings"
	"testing"
)

func TestParseValid(t *testing.T) {
	tests := []struct{ in, want string }{
		{"0", "0"},
		{"-0", "0"},
		{"+0", "0"},
		{"1", "1"},
		{"+1", "1"},
		{"-1", "-1"},
		{"1.", "1"},
		{".5", "0.5"},
		{"-.5", "-0.5"},
		{"0.5", "0.5"},
		{"00012.3400", "12.34"},
		{"1.000000000000000001", "1.000000000000000001"},
		{"0.000000000000000001", "0.000000000000000001"},
		{"-0.000000000000000001", "-0.000000000000000001"},
		{"123456789012345678901", "123456789012345678901"},
		{"0.000000000000000000", "0"},
	}
	for _, tt := range tests {
		d, err := Parse(tt.in)
		if err != nil {
			t.Errorf("Parse(%q) returned %v", tt.in, err)
			continue
		}
		if got := d.String(); got != tt.want {
			t.Errorf("Parse(%q).String() = %q, want %q", tt.in, got, tt.want)
		}
	}
}

func TestParseInvalid(t *testing.T) {
	tests := []struct{ in, wantErr string }{
		{"", "empty string"},
		{"-", "no digits"},
		{"+", "no digits"},
		{".", "no digits"},
		{"abc", "invalid character"},
		{"1a", "invalid character"},
		{"1 ", "invalid character"},
		{" 1", "invalid character"},
		{"1,5", "invalid character"},
		{"1.2.3", "more than one decimal point"},
		{"1e9", "invalid character"},
		{"--1", "invalid character"},
		{"0.1234567890123456789", "more than 18 decimal places"},
		{"1000000000000000000000000000000000000000", "out of range"},
		{"340282366920938463464", "out of range"},
	}
	for _, tt := range tests {
		_, err := Parse(tt.in)
		if err == nil {
			t.Errorf("Parse(%q) returned no error, want %q", tt.in, tt.wantErr)
			continue
		}
		if !strings.Contains(err.Error(), tt.wantErr) {
			t.Errorf("Parse(%q) error = %q, want it to contain %q", tt.in, err.Error(), tt.wantErr)
		}
	}
}

func TestMustParsePanics(t *testing.T) {
	assertPanics(t, "invalid character", func() { MustParse("nope") })
}

func TestStringRoundTrip(t *testing.T) {
	inputs := []string{
		"0",
		"1",
		"-1",
		"0.1",
		"-0.000000000000000001",
		"12345.6789",
		"340282366920938463463.374607431768211455",
		"-340282366920938463463.374607431768211455",
		"18446744073709551616",  // 2**64, forces the multi-chunk printer
		"18446744073709551615.999999999999999999",
	}
	for _, in := range inputs {
		d := MustParse(in)
		if got := d.String(); got != in {
			t.Errorf("round trip of %q gave %q", in, got)
		}
		if again := MustParse(d.String()); again != d {
			t.Errorf("reparsing %q changed the value", in)
		}
	}
}

func TestStringFixed(t *testing.T) {
	tests := []struct {
		in     string
		places int
		want   string
	}{
		{"1.5", 0, "2"},
		{"2.5", 0, "2"},
		{"1", 2, "1.00"},
		{"1.005", 2, "1.00"},
		{"1.015", 2, "1.02"},
		{"-1.015", 2, "-1.02"},
		{"0.000000000000000001", 2, "0.00"},
		{"-0.000000000000000001", 2, "0.00"},
		{"12.3456789", 4, "12.3457"},
		{"1.5", 18, "1.500000000000000000"},
		{"340282366920938463463.374607431768211455", 3, "340282366920938463463.375"},
	}
	for _, tt := range tests {
		got := MustParse(tt.in).StringFixed(tt.places)
		if got != tt.want {
			t.Errorf("StringFixed(%s, %d) = %s, want %s", tt.in, tt.places, got, tt.want)
		}
	}
	assertPanics(t, errPlaces, func() { One().StringFixed(19) })
}

func TestU128Decimal(t *testing.T) {
	tests := []struct {
		hi, lo uint64
		want   string
	}{
		{0, 0, "0"},
		{0, 1, "1"},
		{0, ^uint64(0), "18446744073709551615"},
		{1, 0, "18446744073709551616"},
		{^uint64(0), ^uint64(0), "340282366920938463463374607431768211455"},
	}
	for _, tt := range tests {
		if got := u128Decimal(tt.hi, tt.lo); got != tt.want {
			t.Errorf("u128Decimal(%d,%d) = %s, want %s", tt.hi, tt.lo, got, tt.want)
		}
	}
}

func TestPadDigits(t *testing.T) {
	if got := padDigits(5, 3); got != "005" {
		t.Errorf("padDigits(5,3) = %q", got)
	}
	if got := padDigits(1234, 2); got != "1234" {
		t.Errorf("padDigits truncated: %q", got)
	}
}
