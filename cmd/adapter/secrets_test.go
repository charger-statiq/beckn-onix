package main

import (
	"context"
	"errors"
	"os"
	"strings"
	"testing"
)

const minimalConfig = `
appName: "${TEST_ONIX_APP_NAME}"
http:
  port: "8080"
  timeout:
    read: 5
    write: 5
    idle: 10
`

func writeTempConfig(t *testing.T, body string) string {
	t.Helper()
	path := t.TempDir() + "/adapter.yaml"
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatalf("write config: %v", err)
	}
	return path
}

func stubSecret(t *testing.T, body string, err error) {
	t.Helper()
	orig := fetchSecretJSON
	fetchSecretJSON = func(context.Context, string) (string, error) { return body, err }
	t.Cleanup(func() { fetchSecretJSON = orig })
}

func TestInitConfigExpandsEnv(t *testing.T) {
	t.Setenv("TEST_ONIX_APP_NAME", "from-env")
	cfg, err := initConfig(context.Background(), writeTempConfig(t, minimalConfig))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.AppName != "from-env" {
		t.Errorf("appName = %q, want %q", cfg.AppName, "from-env")
	}
}

func TestInitConfigExpandsFromSecret(t *testing.T) {
	os.Unsetenv("TEST_ONIX_APP_NAME")
	t.Setenv("SECRET_ID", "dev/onix")
	stubSecret(t, `{"TEST_ONIX_APP_NAME":"from-secret"}`, nil)
	t.Cleanup(func() { os.Unsetenv("TEST_ONIX_APP_NAME") })

	cfg, err := initConfig(context.Background(), writeTempConfig(t, minimalConfig))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.AppName != "from-secret" {
		t.Errorf("appName = %q, want %q", cfg.AppName, "from-secret")
	}
}

func TestLoadSecretsIntoEnv(t *testing.T) {
	t.Run("no SECRET_ID is a no-op", func(t *testing.T) {
		os.Unsetenv("SECRET_ID")
		stubSecret(t, "", errors.New("must not be called"))
		if err := loadSecretsIntoEnv(context.Background()); err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
	})

	t.Run("environment wins over the secret", func(t *testing.T) {
		t.Setenv("SECRET_ID", "dev/onix")
		t.Setenv("TEST_ONIX_KEEP", "env-value")
		stubSecret(t, `{"TEST_ONIX_KEEP":"secret-value","TEST_ONIX_NUM":42}`, nil)
		t.Cleanup(func() { os.Unsetenv("TEST_ONIX_NUM") })

		if err := loadSecretsIntoEnv(context.Background()); err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got := os.Getenv("TEST_ONIX_KEEP"); got != "env-value" {
			t.Errorf("TEST_ONIX_KEEP = %q, want env-value", got)
		}
		if got := os.Getenv("TEST_ONIX_NUM"); got != "42" {
			t.Errorf("TEST_ONIX_NUM = %q, want 42 (non-string values are stringified)", got)
		}
	})

	t.Run("fetch failure is returned", func(t *testing.T) {
		t.Setenv("SECRET_ID", "dev/onix")
		stubSecret(t, "", errors.New("access denied"))
		err := loadSecretsIntoEnv(context.Background())
		if err == nil || !strings.Contains(err.Error(), "access denied") {
			t.Errorf("want fetch error, got %v", err)
		}
	})

	t.Run("non-object JSON is rejected", func(t *testing.T) {
		t.Setenv("SECRET_ID", "dev/onix")
		stubSecret(t, `["not","an","object"]`, nil)
		if err := loadSecretsIntoEnv(context.Background()); err == nil {
			t.Error("want error for non-object secret")
		}
	})
}
