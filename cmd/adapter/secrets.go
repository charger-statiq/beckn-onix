package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/secretsmanager"

	"github.com/beckn-one/beckn-onix/pkg/log"
)

const (
	secretIDEnv      = "SECRET_ID"
	awsRegionEnv     = "AWS_REGION"
	defaultAWSRegion = "ap-south-1"
)

// fetchSecretJSON returns the SecretString of one Secrets Manager secret.
// A variable so tests can stub the AWS call.
var fetchSecretJSON = fetchFromSecretsManager

// loadSecretsIntoEnv reads the JSON secret named by SECRET_ID and exports each
// key as an environment variable, so ${KEY} in the config file resolves to it.
// Keys already present in the environment are left alone. No SECRET_ID means
// nothing happens, which keeps local runs free of any AWS dependency.
func loadSecretsIntoEnv(ctx context.Context) error {
	secretID := os.Getenv(secretIDEnv)
	if secretID == "" {
		return nil
	}

	raw, err := fetchSecretJSON(ctx, secretID)
	if err != nil {
		return fmt.Errorf("could not fetch secret %q: %w", secretID, err)
	}

	var values map[string]any
	if err := json.Unmarshal([]byte(raw), &values); err != nil {
		return fmt.Errorf("secret %q is not a JSON object: %w", secretID, err)
	}

	exported := 0
	for key, v := range values {
		if _, set := os.LookupEnv(key); set {
			continue
		}
		var s string
		switch t := v.(type) {
		case string:
			s = t
		default:
			s = fmt.Sprint(t)
		}
		if err := os.Setenv(key, s); err != nil {
			return fmt.Errorf("could not export secret key %q: %w", key, err)
		}
		exported++
	}
	log.Infof(ctx, "Loaded %d keys from secret %q into the environment", exported, secretID)
	return nil
}

func fetchFromSecretsManager(ctx context.Context, secretID string) (string, error) {
	region := os.Getenv(awsRegionEnv)
	if region == "" {
		region = defaultAWSRegion
	}
	cfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		return "", fmt.Errorf("aws config: %w", err)
	}
	out, err := secretsmanager.NewFromConfig(cfg).GetSecretValue(ctx, &secretsmanager.GetSecretValueInput{
		SecretId: &secretID,
	})
	if err != nil {
		return "", err
	}
	if out.SecretString == nil {
		return "", fmt.Errorf("secret %q has no string value", secretID)
	}
	return *out.SecretString, nil
}
