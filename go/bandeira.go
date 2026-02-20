// Package bandeira provides a Go client for the Bandeira feature flag service.
//
// The client polls the Bandeira server at a configurable interval, caches the
// flag state locally, and evaluates strategies in-process — so IsEnabled calls
// are pure in-memory lookups with zero network latency.
//
// Basic usage:
//
//	client, err := bandeira.New(bandeira.Config{
//	    URL:   "http://localhost:8080",
//	    Token: "your-client-token",
//	})
//	if err != nil {
//	    log.Fatal(err)
//	}
//	defer client.Close()
//
//	if client.IsEnabled("my-flag") {
//	    // feature is on
//	}
package bandeira

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"io"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Config configures a Bandeira client.
type Config struct {
	// URL is the base URL of the Bandeira server (e.g. "http://localhost:8080").
	URL string

	// Token is the client API token (created in the Bandeira admin UI).
	Token string

	// PollInterval controls how often the client fetches flags from the server.
	// Defaults to 15 seconds. Ignored when Streaming is true.
	PollInterval time.Duration

	// Streaming enables real-time flag updates via Server-Sent Events (SSE)
	// instead of polling. When true, the client connects to /api/v1/stream
	// and receives flag updates instantly when they change on the server.
	Streaming bool

	// HTTPClient is an optional custom HTTP client. If nil, http.DefaultClient is used.
	// When Streaming is true, the client uses a separate HTTP client with no
	// timeout for the long-lived SSE connection.
	HTTPClient *http.Client

	// Logger is an optional logger for errors. If nil, log.Default() is used.
	Logger *log.Logger
}

// Context provides runtime information for strategy evaluation (user ID,
// properties, remote address, etc.).
type Context struct {
	// UserID is used by the userWithId strategy and as default stickiness.
	UserID string

	// SessionID can be used as an alternative stickiness key.
	SessionID string

	// RemoteAddress is used by the remoteAddress strategy.
	RemoteAddress string

	// Properties are arbitrary key-value pairs used in constraint evaluation.
	Properties map[string]string
}

// Client is a Bandeira feature flag client. It is safe for concurrent use.
type Client struct {
	cfg    Config
	http   *http.Client
	logger *log.Logger

	mu    sync.RWMutex
	flags map[string]flag

	done chan struct{}
	wg   sync.WaitGroup
}

type flag struct {
	Name       string     `json:"name"`
	Enabled    bool       `json:"enabled"`
	Strategies []strategy `json:"strategies"`
}

type strategy struct {
	Name       string         `json:"name"`
	Parameters map[string]any `json:"parameters"`
	Constraints []constraint  `json:"constraints"`
}

type constraint struct {
	ContextName     string   `json:"context_name"`
	Operator        string   `json:"operator"`
	Values          []string `json:"values"`
	Inverted        bool     `json:"inverted"`
	CaseInsensitive bool     `json:"case_insensitive"`
}

type apiResponse struct {
	Flags []flag `json:"flags"`
}

// New creates a new Bandeira client and starts the background poller.
// Call Close() when done to stop polling.
func New(cfg Config) (*Client, error) {
	if cfg.URL == "" {
		return nil, fmt.Errorf("bandeira: URL is required")
	}
	if cfg.Token == "" {
		return nil, fmt.Errorf("bandeira: Token is required")
	}
	if cfg.PollInterval <= 0 {
		cfg.PollInterval = 15 * time.Second
	}

	httpClient := cfg.HTTPClient
	if httpClient == nil {
		httpClient = &http.Client{Timeout: 10 * time.Second}
	}

	logger := cfg.Logger
	if logger == nil {
		logger = log.Default()
	}

	c := &Client{
		cfg:    cfg,
		http:   httpClient,
		logger: logger,
		flags:  make(map[string]flag),
		done:   make(chan struct{}),
	}

	// Initial fetch — fail fast if server is unreachable.
	if err := c.fetch(); err != nil {
		return nil, fmt.Errorf("bandeira: initial fetch failed: %w", err)
	}

	c.wg.Add(1)
	if cfg.Streaming {
		go c.stream()
	} else {
		go c.poll()
	}

	return c, nil
}

// Close stops the background poller and releases resources.
func (c *Client) Close() {
	close(c.done)
	c.wg.Wait()
}

// IsEnabled returns true if the given flag is enabled. Without a Context,
// only the enabled/disabled state is checked (strategies that need context
// will evaluate to false). Pass one Context to enable full strategy evaluation.
func (c *Client) IsEnabled(name string, ctx ...Context) bool {
	c.mu.RLock()
	f, ok := c.flags[name]
	c.mu.RUnlock()

	if !ok || !f.Enabled {
		return false
	}

	// Enabled with no strategies → ON for everyone.
	if len(f.Strategies) == 0 {
		return true
	}

	var evalCtx Context
	if len(ctx) > 0 {
		evalCtx = ctx[0]
	}

	// OR logic between strategies — if ANY returns true, flag is ON.
	for _, s := range f.Strategies {
		if evaluateStrategy(s, evalCtx) {
			return true
		}
	}

	return false
}

// AllFlags returns a snapshot of all known flags and their enabled state.
func (c *Client) AllFlags() map[string]bool {
	c.mu.RLock()
	defer c.mu.RUnlock()

	result := make(map[string]bool, len(c.flags))
	for k, v := range c.flags {
		result[k] = v.Enabled
	}
	return result
}

// poll runs the background polling loop.
func (c *Client) poll() {
	defer c.wg.Done()
	ticker := time.NewTicker(c.cfg.PollInterval)
	defer ticker.Stop()

	for {
		select {
		case <-c.done:
			return
		case <-ticker.C:
			if err := c.fetch(); err != nil {
				c.logger.Printf("bandeira: poll failed: %v", err)
			}
		}
	}
}

// fetch retrieves flags from the server and updates the local cache.
func (c *Client) fetch() error {
	url := strings.TrimRight(c.cfg.URL, "/") + "/api/v1/flags"

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.cfg.Token)

	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("unexpected status %d: %s", resp.StatusCode, string(body))
	}

	var apiResp apiResponse
	if err := json.NewDecoder(resp.Body).Decode(&apiResp); err != nil {
		return fmt.Errorf("failed to decode response: %w", err)
	}

	m := make(map[string]flag, len(apiResp.Flags))
	for _, f := range apiResp.Flags {
		m[f.Name] = f
	}

	c.mu.Lock()
	c.flags = m
	c.mu.Unlock()

	return nil
}

// stream connects to the SSE endpoint and updates flags in real-time.
// On connection drop, it reconnects with exponential backoff.
func (c *Client) stream() {
	defer c.wg.Done()

	const (
		minBackoff = 1 * time.Second
		maxBackoff = 30 * time.Second
	)
	backoff := minBackoff

	// SSE connections must not have a timeout.
	sseClient := &http.Client{Timeout: 0}

	for {
		select {
		case <-c.done:
			return
		default:
		}

		err := c.connectSSE(sseClient)
		if err != nil {
			c.logger.Printf("bandeira: stream disconnected: %v", err)
		}

		// Check if we're shutting down before reconnecting.
		select {
		case <-c.done:
			return
		default:
		}

		c.logger.Printf("bandeira: reconnecting in %v", backoff)
		select {
		case <-c.done:
			return
		case <-time.After(backoff):
		}

		// Exponential backoff with cap.
		backoff *= 2
		if backoff > maxBackoff {
			backoff = maxBackoff
		}
	}
}

// connectSSE establishes a single SSE connection and processes events until
// the connection drops or the client is closed. Returns nil on clean shutdown.
func (c *Client) connectSSE(sseClient *http.Client) error {
	url := strings.TrimRight(c.cfg.URL, "/") + "/api/v1/stream"

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Cancel the HTTP request when the client is closed.
	go func() {
		select {
		case <-c.done:
			cancel()
		case <-ctx.Done():
		}
	}()

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.cfg.Token)
	req.Header.Set("Accept", "text/event-stream")

	resp, err := sseClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("unexpected status %d: %s", resp.StatusCode, string(body))
	}

	scanner := bufio.NewScanner(resp.Body)
	var eventType string
	var dataLines []string

	for scanner.Scan() {
		line := scanner.Text()

		if line == "" {
			// Empty line = end of event.
			if eventType == "flags" && len(dataLines) > 0 {
				data := strings.Join(dataLines, "\n")
				c.applyFlagData([]byte(data))
				// Reset backoff on successful event.
			}
			eventType = ""
			dataLines = nil
			continue
		}

		if strings.HasPrefix(line, "event: ") {
			eventType = strings.TrimPrefix(line, "event: ")
		} else if strings.HasPrefix(line, "data: ") {
			dataLines = append(dataLines, strings.TrimPrefix(line, "data: "))
		}
		// Ignore comments (lines starting with ':') and other fields.
	}

	if err := scanner.Err(); err != nil {
		return err
	}
	return fmt.Errorf("connection closed by server")
}

// applyFlagData parses a JSON flag payload and updates the local cache.
func (c *Client) applyFlagData(data []byte) {
	var apiResp apiResponse
	if err := json.Unmarshal(data, &apiResp); err != nil {
		c.logger.Printf("bandeira: failed to parse SSE data: %v", err)
		return
	}

	m := make(map[string]flag, len(apiResp.Flags))
	for _, f := range apiResp.Flags {
		m[f.Name] = f
	}

	c.mu.Lock()
	c.flags = m
	c.mu.Unlock()
}

// ── Strategy evaluation ───────────────────────────────────────────────────

func evaluateStrategy(s strategy, ctx Context) bool {
	// AND logic — all constraints must pass.
	for _, con := range s.Constraints {
		if !evaluateConstraint(con, ctx) {
			return false
		}
	}

	switch s.Name {
	case "default":
		return true

	case "userWithId":
		return evalUserWithId(s, ctx)

	case "gradualRollout":
		return evalGradualRollout(s, ctx)

	case "remoteAddress":
		return evalRemoteAddress(s, ctx)

	default:
		// Unknown strategy → skip (fail open for constraints-only strategies).
		return true
	}
}

func evalUserWithId(s strategy, ctx Context) bool {
	raw, ok := s.Parameters["userIds"]
	if !ok {
		return false
	}
	userIds, ok := raw.(string)
	if !ok {
		return false
	}
	// Split on both commas and newlines to support values from the UI
	// textarea (newline-separated) and legacy comma-separated format.
	for _, id := range splitMulti(userIds) {
		if id == ctx.UserID {
			return true
		}
	}
	return false
}

func evalGradualRollout(s strategy, ctx Context) bool {
	rolloutRaw, ok := s.Parameters["rollout"]
	if !ok {
		return false
	}

	var rollout int
	switch v := rolloutRaw.(type) {
	case float64:
		rollout = int(v)
	case int:
		rollout = v
	case string:
		var err error
		rollout, err = strconv.Atoi(v)
		if err != nil {
			return false
		}
	default:
		return false
	}

	if rollout >= 100 {
		return true
	}
	if rollout <= 0 {
		return false
	}

	stickiness := "userId"
	if v, ok := s.Parameters["stickiness"].(string); ok {
		stickiness = v
	}

	var stickinessValue string
	switch stickiness {
	case "userId":
		stickinessValue = ctx.UserID
	case "sessionId":
		stickinessValue = ctx.SessionID
	default:
		if v, ok := ctx.Properties[stickiness]; ok {
			stickinessValue = v
		}
	}

	if stickinessValue == "" {
		return false
	}

	groupId, _ := s.Parameters["groupId"].(string)
	normalized := normalizedHash(stickinessValue + groupId)

	return normalized < uint32(rollout)
}

func evalRemoteAddress(s strategy, ctx Context) bool {
	// Accept both "ips" (UI) and "IPs" (legacy) parameter keys.
	raw, ok := s.Parameters["ips"]
	if !ok {
		raw, ok = s.Parameters["IPs"]
	}
	if !ok {
		return false
	}
	ips, ok := raw.(string)
	if !ok {
		return false
	}
	addr := ctx.RemoteAddress
	for _, entry := range splitMulti(ips) {
		if entry == addr {
			return true
		}
		// Simple CIDR prefix match (e.g. "192.168.1." matches "192.168.1.100").
		if strings.HasSuffix(entry, ".") && strings.HasPrefix(addr, entry) {
			return true
		}
	}
	return false
}

// ── Constraint evaluation ─────────────────────────────────────────────────

func evaluateConstraint(con constraint, ctx Context) bool {
	ctxValue := getContextValue(con.ContextName, ctx)

	result := evalOperator(con.Operator, ctxValue, con.Values, con.CaseInsensitive)

	if con.Inverted {
		return !result
	}
	return result
}

func getContextValue(name string, ctx Context) string {
	switch name {
	case "userId":
		return ctx.UserID
	case "sessionId":
		return ctx.SessionID
	case "remoteAddress":
		return ctx.RemoteAddress
	default:
		if ctx.Properties != nil {
			return ctx.Properties[name]
		}
		return ""
	}
}

func evalOperator(op, ctxValue string, values []string, caseInsensitive bool) bool {
	cv := ctxValue
	if caseInsensitive {
		cv = strings.ToLower(cv)
	}

	switch op {
	case "IN":
		for _, v := range values {
			cmp := v
			if caseInsensitive {
				cmp = strings.ToLower(cmp)
			}
			if cv == cmp {
				return true
			}
		}
		return false

	case "NOT_IN":
		for _, v := range values {
			cmp := v
			if caseInsensitive {
				cmp = strings.ToLower(cmp)
			}
			if cv == cmp {
				return false
			}
		}
		return true

	case "STR_CONTAINS":
		for _, v := range values {
			cmp := v
			if caseInsensitive {
				cmp = strings.ToLower(cmp)
			}
			if strings.Contains(cv, cmp) {
				return true
			}
		}
		return false

	case "STR_STARTS_WITH":
		for _, v := range values {
			cmp := v
			if caseInsensitive {
				cmp = strings.ToLower(cmp)
			}
			if strings.HasPrefix(cv, cmp) {
				return true
			}
		}
		return false

	case "STR_ENDS_WITH":
		for _, v := range values {
			cmp := v
			if caseInsensitive {
				cmp = strings.ToLower(cmp)
			}
			if strings.HasSuffix(cv, cmp) {
				return true
			}
		}
		return false

	case "NUM_EQ", "NUM_GT", "NUM_GTE", "NUM_LT", "NUM_LTE":
		num, err := strconv.ParseFloat(cv, 64)
		if err != nil {
			return false
		}
		for _, v := range values {
			target, err := strconv.ParseFloat(v, 64)
			if err != nil {
				continue
			}
			switch op {
			case "NUM_EQ":
				if num == target {
					return true
				}
			case "NUM_GT":
				if num > target {
					return true
				}
			case "NUM_GTE":
				if num >= target {
					return true
				}
			case "NUM_LT":
				if num < target {
					return true
				}
			case "NUM_LTE":
				if num <= target {
					return true
				}
			}
		}
		return false

	case "DATE_AFTER", "DATE_BEFORE":
		t, err := time.Parse(time.RFC3339, cv)
		if err != nil {
			return false
		}
		for _, v := range values {
			target, err := time.Parse(time.RFC3339, v)
			if err != nil {
				continue
			}
			switch op {
			case "DATE_AFTER":
				if t.After(target) {
					return true
				}
			case "DATE_BEFORE":
				if t.Before(target) {
					return true
				}
			}
		}
		return false

	default:
		return false
	}
}

// splitMulti splits a string on commas and newlines, trims whitespace, and
// drops empty entries. This handles both the UI textarea format (newlines)
// and the legacy comma-separated format.
func splitMulti(s string) []string {
	// Normalize newlines to commas so we can do a single split.
	s = strings.ReplaceAll(s, "\r\n", ",")
	s = strings.ReplaceAll(s, "\n", ",")
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

// normalizedHash returns a value 0-99 for consistent bucketing.
func normalizedHash(s string) uint32 {
	h := fnv.New32a()
	h.Write([]byte(s))
	return h.Sum32() % 100
}
