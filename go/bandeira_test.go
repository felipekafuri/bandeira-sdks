package bandeira

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func newTestServer(flags []flag) *httptest.Server {
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer test-token" {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		json.NewEncoder(w).Encode(apiResponse{Flags: flags})
	}))
}

func TestIsEnabled_BasicToggle(t *testing.T) {
	srv := newTestServer([]flag{
		{Name: "on-flag", Enabled: true},
		{Name: "off-flag", Enabled: false},
	})
	defer srv.Close()

	c, err := New(Config{URL: srv.URL, Token: "test-token", PollInterval: time.Hour})
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()

	if !c.IsEnabled("on-flag") {
		t.Error("expected on-flag to be enabled")
	}
	if c.IsEnabled("off-flag") {
		t.Error("expected off-flag to be disabled")
	}
	if c.IsEnabled("unknown-flag") {
		t.Error("expected unknown flag to be disabled")
	}
}

func TestIsEnabled_DefaultStrategy(t *testing.T) {
	srv := newTestServer([]flag{
		{
			Name:    "with-default",
			Enabled: true,
			Strategies: []strategy{
				{Name: "default"},
			},
		},
	})
	defer srv.Close()

	c, err := New(Config{URL: srv.URL, Token: "test-token", PollInterval: time.Hour})
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()

	if !c.IsEnabled("with-default") {
		t.Error("expected flag with default strategy to be enabled")
	}
}

func TestIsEnabled_UserWithId(t *testing.T) {
	srv := newTestServer([]flag{
		{
			Name:    "user-flag",
			Enabled: true,
			Strategies: []strategy{
				{Name: "userWithId", Parameters: map[string]any{"userIds": "1,2,42"}},
			},
		},
	})
	defer srv.Close()

	c, err := New(Config{URL: srv.URL, Token: "test-token", PollInterval: time.Hour})
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()

	if !c.IsEnabled("user-flag", Context{UserID: "42"}) {
		t.Error("expected user 42 to match")
	}
	if c.IsEnabled("user-flag", Context{UserID: "99"}) {
		t.Error("expected user 99 to not match")
	}
	if c.IsEnabled("user-flag") {
		t.Error("expected no context to not match userWithId")
	}
}

func TestIsEnabled_GradualRollout(t *testing.T) {
	srv := newTestServer([]flag{
		{
			Name:    "rollout-100",
			Enabled: true,
			Strategies: []strategy{
				{Name: "gradualRollout", Parameters: map[string]any{"rollout": float64(100)}},
			},
		},
		{
			Name:    "rollout-0",
			Enabled: true,
			Strategies: []strategy{
				{Name: "gradualRollout", Parameters: map[string]any{"rollout": float64(0)}},
			},
		},
	})
	defer srv.Close()

	c, err := New(Config{URL: srv.URL, Token: "test-token", PollInterval: time.Hour})
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()

	if !c.IsEnabled("rollout-100", Context{UserID: "anyone"}) {
		t.Error("expected 100% rollout to be enabled")
	}
	if c.IsEnabled("rollout-0", Context{UserID: "anyone"}) {
		t.Error("expected 0% rollout to be disabled")
	}
}

func TestIsEnabled_Constraint_IN(t *testing.T) {
	srv := newTestServer([]flag{
		{
			Name:    "constrained",
			Enabled: true,
			Strategies: []strategy{
				{
					Name: "default",
					Constraints: []constraint{
						{ContextName: "companyId", Operator: "IN", Values: []string{"1", "2", "3"}},
					},
				},
			},
		},
	})
	defer srv.Close()

	c, err := New(Config{URL: srv.URL, Token: "test-token", PollInterval: time.Hour})
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()

	if !c.IsEnabled("constrained", Context{Properties: map[string]string{"companyId": "2"}}) {
		t.Error("expected companyId 2 to match IN constraint")
	}
	if c.IsEnabled("constrained", Context{Properties: map[string]string{"companyId": "99"}}) {
		t.Error("expected companyId 99 to not match")
	}
}

func TestIsEnabled_Constraint_Inverted(t *testing.T) {
	srv := newTestServer([]flag{
		{
			Name:    "inverted",
			Enabled: true,
			Strategies: []strategy{
				{
					Name: "default",
					Constraints: []constraint{
						{ContextName: "plan", Operator: "IN", Values: []string{"free"}, Inverted: true},
					},
				},
			},
		},
	})
	defer srv.Close()

	c, err := New(Config{URL: srv.URL, Token: "test-token", PollInterval: time.Hour})
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()

	// "free" is in the list → inverted → false
	if c.IsEnabled("inverted", Context{Properties: map[string]string{"plan": "free"}}) {
		t.Error("expected free plan to be excluded by inverted constraint")
	}
	// "enterprise" is NOT in the list → inverted → true
	if !c.IsEnabled("inverted", Context{Properties: map[string]string{"plan": "enterprise"}}) {
		t.Error("expected enterprise plan to pass inverted constraint")
	}
}

func TestIsEnabled_UserWithId_Newlines(t *testing.T) {
	srv := newTestServer([]flag{
		{
			Name:    "user-newline",
			Enabled: true,
			Strategies: []strategy{
				{Name: "userWithId", Parameters: map[string]any{"userIds": "1\n2\n42"}},
			},
		},
	})
	defer srv.Close()

	c, err := New(Config{URL: srv.URL, Token: "test-token", PollInterval: time.Hour})
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()

	if !c.IsEnabled("user-newline", Context{UserID: "42"}) {
		t.Error("expected user 42 to match with newline-separated ids")
	}
	if c.IsEnabled("user-newline", Context{UserID: "99"}) {
		t.Error("expected user 99 to not match")
	}
}

func TestIsEnabled_Constraint_CaseInsensitive(t *testing.T) {
	srv := newTestServer([]flag{
		{
			Name:    "ci-flag",
			Enabled: true,
			Strategies: []strategy{
				{
					Name: "default",
					Constraints: []constraint{
						{ContextName: "country", Operator: "IN", Values: []string{"Brazil", "Portugal"}, CaseInsensitive: true},
					},
				},
			},
		},
	})
	defer srv.Close()

	c, err := New(Config{URL: srv.URL, Token: "test-token", PollInterval: time.Hour})
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()

	if !c.IsEnabled("ci-flag", Context{Properties: map[string]string{"country": "brazil"}}) {
		t.Error("expected case-insensitive match for 'brazil'")
	}
	if !c.IsEnabled("ci-flag", Context{Properties: map[string]string{"country": "PORTUGAL"}}) {
		t.Error("expected case-insensitive match for 'PORTUGAL'")
	}
	if c.IsEnabled("ci-flag", Context{Properties: map[string]string{"country": "spain"}}) {
		t.Error("expected 'spain' to not match")
	}
}

func TestIsEnabled_Constraint_STR_CONTAINS(t *testing.T) {
	srv := newTestServer([]flag{
		{
			Name:    "contains-flag",
			Enabled: true,
			Strategies: []strategy{
				{
					Name: "default",
					Constraints: []constraint{
						{ContextName: "email", Operator: "STR_CONTAINS", Values: []string{"@acme.com"}},
					},
				},
			},
		},
	})
	defer srv.Close()

	c, err := New(Config{URL: srv.URL, Token: "test-token", PollInterval: time.Hour})
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()

	if !c.IsEnabled("contains-flag", Context{Properties: map[string]string{"email": "user@acme.com"}}) {
		t.Error("expected 'user@acme.com' to contain '@acme.com'")
	}
	if c.IsEnabled("contains-flag", Context{Properties: map[string]string{"email": "user@other.com"}}) {
		t.Error("expected 'user@other.com' to not contain '@acme.com'")
	}
}

func TestIsEnabled_RemoteAddress(t *testing.T) {
	srv := newTestServer([]flag{
		{
			Name:    "ip-flag",
			Enabled: true,
			Strategies: []strategy{
				{Name: "remoteAddress", Parameters: map[string]any{"ips": "10.0.0.1\n192.168.1."}},
			},
		},
		{
			Name:    "ip-flag-legacy",
			Enabled: true,
			Strategies: []strategy{
				{Name: "remoteAddress", Parameters: map[string]any{"IPs": "10.0.0.1,192.168.1."}},
			},
		},
	})
	defer srv.Close()

	c, err := New(Config{URL: srv.URL, Token: "test-token", PollInterval: time.Hour})
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()

	if !c.IsEnabled("ip-flag", Context{RemoteAddress: "10.0.0.1"}) {
		t.Error("expected 10.0.0.1 to match")
	}
	if !c.IsEnabled("ip-flag", Context{RemoteAddress: "192.168.1.100"}) {
		t.Error("expected 192.168.1.100 to match prefix")
	}
	if c.IsEnabled("ip-flag", Context{RemoteAddress: "172.16.0.1"}) {
		t.Error("expected 172.16.0.1 to not match")
	}

	if !c.IsEnabled("ip-flag-legacy", Context{RemoteAddress: "10.0.0.1"}) {
		t.Error("expected legacy IPs key to work")
	}
}

func TestAllFlags(t *testing.T) {
	srv := newTestServer([]flag{
		{Name: "a", Enabled: true},
		{Name: "b", Enabled: false},
	})
	defer srv.Close()

	c, err := New(Config{URL: srv.URL, Token: "test-token", PollInterval: time.Hour})
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()

	flags := c.AllFlags()
	if !flags["a"] {
		t.Error("expected a to be true")
	}
	if flags["b"] {
		t.Error("expected b to be false")
	}
}

func TestNew_InvalidToken(t *testing.T) {
	srv := newTestServer(nil)
	defer srv.Close()

	_, err := New(Config{URL: srv.URL, Token: "wrong-token", PollInterval: time.Hour})
	if err == nil {
		t.Error("expected error with invalid token")
	}
}

func TestNew_MissingURL(t *testing.T) {
	_, err := New(Config{Token: "test"})
	if err == nil {
		t.Error("expected error with missing URL")
	}
}

func TestNew_MissingToken(t *testing.T) {
	_, err := New(Config{URL: "http://localhost"})
	if err == nil {
		t.Error("expected error with missing token")
	}
}
