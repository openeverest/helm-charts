package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"

	"github.com/opencontainers/go-digest"
	"github.com/opencontainers/image-spec/specs-go"
	ocispec "github.com/opencontainers/image-spec/specs-go/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"oras.land/oras-go/v2/registry/remote/auth"
)

// fakeRegistry serves one manifest and its config blob under
// /v2/charts/plugin-hub, as a registry serves a chart Helm pushed.
func fakeRegistry(t *testing.T, configMediaType string, config []byte) string {
	t.Helper()

	configDesc := ocispec.Descriptor{
		MediaType: configMediaType,
		Digest:    digest.FromBytes(config),
		Size:      int64(len(config)),
	}
	manifest, err := json.Marshal(ocispec.Manifest{
		Versioned: specs.Versioned{SchemaVersion: 2},
		MediaType: ocispec.MediaTypeImageManifest,
		Config:    configDesc,
		Layers:    []ocispec.Descriptor{},
	})
	require.NoError(t, err)

	serve := func(w http.ResponseWriter, mediaType string, body []byte) {
		w.Header().Set("Content-Type", mediaType)
		w.Header().Set("Content-Length", strconv.Itoa(len(body)))
		w.Header().Set("Docker-Content-Digest", digest.FromBytes(body).String())
		_, _ = w.Write(body)
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v2/charts/plugin-hub/manifests/0.1.18":
			serve(w, ocispec.MediaTypeImageManifest, manifest)
		case "/v2/charts/plugin-hub/blobs/" + configDesc.Digest.String():
			serve(w, "application/octet-stream", config)
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	return strings.TrimPrefix(srv.URL, "http://")
}

func TestOCIFetcher(t *testing.T) {
	t.Parallel()

	stamped := []byte(`{"name":"plugin-hub","version":"0.1.18","apiVersion":"v2",` +
		`"annotations":{"openeverest.io/contract-version":"2.1.0"}}`)

	tests := []struct {
		name            string
		configMediaType string
		config          []byte
		tag             string
		want            Metadata
		wantErr         string
	}{
		{
			name:            "stamped chart",
			configMediaType: helmConfigMediaType,
			config:          stamped,
			tag:             "0.1.18",
			want: Metadata{
				Name:        "plugin-hub",
				Version:     "0.1.18",
				Annotations: map[string]string{"openeverest.io/contract-version": "2.1.0"},
			},
		},
		{
			name:            "unstamped chart",
			configMediaType: helmConfigMediaType,
			config:          []byte(`{"name":"plugin-hub","version":"0.1.18","apiVersion":"v2"}`),
			tag:             "0.1.18",
			want:            Metadata{Name: "plugin-hub", Version: "0.1.18"},
		},
		{
			name:            "not a chart",
			configMediaType: ocispec.MediaTypeImageConfig,
			config:          []byte(`{}`),
			tag:             "0.1.18",
			wantErr:         `is not a Helm chart: its config has media type "application/vnd.oci.image.config.v1+json"`,
		},
		{
			name:            "unknown tag",
			configMediaType: helmConfigMediaType,
			config:          stamped,
			tag:             "0.1.19",
			wantErr:         "fetch the manifest of",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()

			host := fakeRegistry(t, tt.configMediaType, tt.config)
			f := &ociFetcher{client: &auth.Client{}, plainHTTP: true}

			got, err := f.Fetch(t.Context(), host+"/charts/plugin-hub:"+tt.tag)
			if tt.wantErr != "" {
				require.Error(t, err)
				assert.Contains(t, err.Error(), tt.wantErr)
				return
			}
			require.NoError(t, err)
			assert.Equal(t, tt.want, got)
		})
	}
}
