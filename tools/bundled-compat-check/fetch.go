package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"

	ocispec "github.com/opencontainers/image-spec/specs-go/v1"
	"oras.land/oras-go/v2"
	"oras.land/oras-go/v2/content"
	"oras.land/oras-go/v2/registry/remote"
	"oras.land/oras-go/v2/registry/remote/auth"
	"oras.land/oras-go/v2/registry/remote/retry"
)

const (
	// helmConfigMediaType is the media type of the config blob of a Helm
	// chart in an OCI registry: its Chart.yaml as JSON.
	helmConfigMediaType = "application/vnd.cncf.helm.config.v1+json"
	// maxConfigBytes bounds the config blob read into memory; a Chart.yaml is
	// a few KiB.
	maxConfigBytes = 1 << 20
)

// ociFetcher reads chart metadata from OCI registries, anonymously: the
// charts the core chart bundles are public.
type ociFetcher struct {
	client    remote.Client
	plainHTTP bool
}

func newOCIFetcher() *ociFetcher {
	return &ociFetcher{
		client: &auth.Client{
			Client: retry.DefaultClient,
			Header: http.Header{"User-Agent": {"openeverest-bundled-compat-check"}},
			Cache:  auth.NewCache(),
		},
	}
}

// Fetch reads the Chart.yaml of the chart at ref from its config blob, which
// avoids downloading the chart itself.
func (f *ociFetcher) Fetch(ctx context.Context, ref string) (Metadata, error) {
	repo, err := remote.NewRepository(ref)
	if err != nil {
		return Metadata{}, fmt.Errorf("parse reference %s: %w", ref, err)
	}
	repo.Client = f.client
	repo.PlainHTTP = f.plainHTTP

	_, raw, err := oras.FetchBytes(ctx, repo, repo.Reference.Reference, oras.DefaultFetchBytesOptions)
	if err != nil {
		return Metadata{}, fmt.Errorf("fetch the manifest of %s: %w", ref, err)
	}
	var manifest ocispec.Manifest
	if err := json.Unmarshal(raw, &manifest); err != nil {
		return Metadata{}, fmt.Errorf("parse the manifest of %s: %w", ref, err)
	}
	if manifest.Config.MediaType != helmConfigMediaType {
		return Metadata{}, fmt.Errorf("%s is not a Helm chart: its config has media type %q, not %q",
			ref, manifest.Config.MediaType, helmConfigMediaType)
	}
	if manifest.Config.Size > maxConfigBytes {
		return Metadata{}, fmt.Errorf("the config of %s is %d bytes, above the %d-byte limit for a Chart.yaml",
			ref, manifest.Config.Size, maxConfigBytes)
	}

	// FetchAll verifies the blob against the digest in the manifest.
	config, err := content.FetchAll(ctx, repo, manifest.Config)
	if err != nil {
		return Metadata{}, fmt.Errorf("fetch the config of %s: %w", ref, err)
	}
	var md Metadata
	if err := json.Unmarshal(config, &md); err != nil {
		return Metadata{}, fmt.Errorf("parse the config of %s: %w", ref, err)
	}
	return md, nil
}
